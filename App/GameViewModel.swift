// 엔진 상태를 SwiftUI 에 노출하는 뷰모델.
// 규칙 변경은 전부 엔진 함수를 통한다(여기선 입력 수집·턴 진행·AI 구동만).

import SwiftUI

enum GameMode: String, CaseIterable, Identifiable {
    case single = "싱글"   // 오프라인: 나 vs AI
    case casual = "일반"   // 온라인 일반전(방 기반)
    case ranked = "랭크"   // 온라인 랭크전 — 준비 중
    var id: String { rawValue }
    /// 랭크는 준비 중.
    var isAvailable: Bool { self != .ranked }
    /// 온라인 서버가 필요한 모드.
    var isOnline: Bool { self == .casual || self == .ranked }
}

/// 현재 턴의 단계.
enum TurnPhase: Equatable {
    case main         // 메인 액션 대기(사람)
    case evolve       // 메인 액션 후 진화 선택(사람)
    case aiThinking   // AI 차례
    case gameOver
}

@MainActor
@Observable
final class GameViewModel {
    private(set) var state: GameState
    let mode: GameMode
    let playerNames: [String]

    private(set) var phase: TurnPhase = .main
    /// 구슬 선택: 색 → 선택 개수(1=서로 다른 색 take3용, 2=같은 색 take2). 탭으로 0→1→2→0 순환.
    private(set) var ballPick: [Color: Int] = [:]
    /// 마지막 로그 메시지(간단 피드백).
    private(set) var lastMessage: String = ""
    /// 진화 후보(evolve 단계).
    private(set) var pendingEvolutions: [Evolution] = []

    private let aiRng: Rng

    init(mode: GameMode, numPlayers: Int, seed: UInt32) {
        self.mode = mode
        // 싱글: P0 만 사람, 나머지 AI.
        self.state = createGame(seed: seed, numPlayers: numPlayers, humanIndex: 0)
        self.aiRng = Rng(seed: seed &+ 12321)
        self.playerNames = (0..<numPlayers).map { i in i == 0 ? "나" : "AI \(i)" }
        resolvePhaseForCurrent()
    }

    // MARK: - 조회

    var currentPlayer: PlayerState { state.players[state.currentPlayer] }
    var isHumanTurn: Bool {
        if state.ended { return false }
        return state.currentPlayer == 0
    }
    var winner: Int? { state.ended ? winnerId(state) : nil }
    var ranking: [Int] { rankPlayers(state) }

    func points(_ playerIdx: Int) -> Int { playerPoints(state.players[playerIdx]) }

    /// 보드 특정 tier 슬롯 카드 id.
    func boardSlots(_ tier: Tier) -> [String] { state.board[tier] ?? [] }
    func deckCount(_ tier: Tier) -> Int { (state.decks[tier] ?? []).count }

    /// 현재 사람 플레이어가 이 카드를 획득 가능한가.
    func canAcquire(_ cardId: String) -> Bool {
        guard isHumanTurn, phase == .main else { return false }
        return canApplyMainAction(state, .acquire(cardId: cardId, pay: computePay(currentPlayer, cardOf(cardId)) ?? [:]))
    }
    func canReserveCard(_ cardId: String) -> Bool {
        guard isHumanTurn, phase == .main else { return false }
        return canApplyMainAction(state, .reserve(cardId: cardId))
    }
    func canReserveBlind(_ tier: Int) -> Bool {
        guard isHumanTurn, phase == .main else { return false }
        return canApplyMainAction(state, .reserveBlind(tier: tier))
    }
    func supplyCount(_ c: BallColor) -> Int { state.supply[c] ?? 0 }

    // MARK: - 구슬 집기 (탭만으로 0→1→2→0 순환)

    /// 이 색이 현재 몇 개 선택됐는지(0/1/2).
    func pickedCount(_ c: Color) -> Int { ballPick[c] ?? 0 }

    /// 표시용: 선택 구슬을 개수만큼 펼친 목록.
    var pickedList: [Color] { ballPick.flatMap { c, n in Array(repeating: c, count: n) } }

    /// 같은 색 2개(take2) 모드인지.
    private var isTake2Mode: Bool { ballPick.values.contains(2) }

    /// 구슬 탭: 0→1→(같은 색 2개 가능하면 2, 아니면 해제)→0.
    func tapColor(_ c: Color) {
        guard isHumanTurn, phase == .main else { return }
        switch pickedCount(c) {
        case 0:
            // 같은 색 2개 모드 진행 중이면 다른 색은 추가 불가.
            if isTake2Mode { return }
            guard supplyCount(BallColor(rawValue: c.rawValue)!) > 0 else { return }
            guard ballPick.count < 3 else { return }
            var next = ballPick
            next[c] = 1
            // 손 여유칸 등 take3 합법성 확인 후 반영.
            guard canApplyMainAction(state, .take3(colors: Array(next.keys))) else { return }
            ballPick = next
        case 1:
            // 단독 선택이고 같은 색 2개가 가능하면 → 2, 아니면 해제.
            if ballPick.count == 1 && canTake2(c) {
                ballPick[c] = 2
            } else {
                ballPick[c] = nil
            }
        default: // 2 → 해제
            ballPick[c] = nil
        }
    }

    func canTake2(_ c: Color) -> Bool {
        guard isHumanTurn, phase == .main else { return false }
        return canApplyMainAction(state, .take2(color: c))
    }

    /// 선택 상태에 대응하는 액션(2 있으면 take2, 아니면 take3).
    private var ballAction: MainAction? {
        if let two = ballPick.first(where: { $0.value == 2 }) {
            return .take2(color: two.key)
        }
        return ballPick.isEmpty ? nil : .take3(colors: Array(ballPick.keys))
    }

    var canConfirmBalls: Bool {
        guard isHumanTurn, phase == .main, let a = ballAction else { return false }
        return canApplyMainAction(state, a)
    }

    func confirmBalls() {
        guard canConfirmBalls, let a = ballAction else { return }
        performMain(a)
    }

    func clearBalls() { ballPick = [:] }

    // MARK: - 카드 액션

    func acquire(_ cardId: String) {
        guard let pay = computePay(currentPlayer, cardOf(cardId)) else { return }
        performMain(.acquire(cardId: cardId, pay: pay))
    }
    func reserve(_ cardId: String) { performMain(.reserve(cardId: cardId)) }
    func reserveBlind(_ tier: Int) { performMain(.reserveBlind(tier: tier)) }

    /// 찜은 되지만 찜코인을 못 받는 상황(손패 10개 꽉 참 or 남은 찜코인 0개) → 확인 필요.
    func reserveNeedsConfirm(_ cardId: String) -> Bool {
        guard canReserveCard(cardId) else { return false }
        let handFull = handBallCount(currentPlayer) >= MAX_BALLS_IN_HAND
        let noCoin = supplyCount(.gold) == 0
        return handFull || noCoin
    }

    /// 카드 상세의 '진화': 이 카드를 대상으로 하는 합법 진화가 있으면 가능(턴당 1회).
    func canEvolveInto(_ cardId: String) -> Bool {
        guard isHumanTurn, phase == .main, !state.evolvedThisTurn else { return false }
        return legalEvolutions(state).contains { $0.targetId == cardId }
    }

    func evolveInto(_ cardId: String) {
        guard canEvolveInto(cardId),
              let e = legalEvolutions(state).first(where: { $0.targetId == cardId }) else { return }
        applyEvolution(state, e)
        lastMessage = "\(cardOf(cardId).name)(으)로 진화!"
        endHumanTurn()
    }

    // MARK: - 메인 액션 실행 → 진화 단계 or 턴 종료

    private func performMain(_ action: MainAction) {
        guard isHumanTurn, phase == .main, canApplyMainAction(state, action) else { return }
        applyMainAction(state, action)
        ballPick = [:]
        lastMessage = describe(action)
        pendingEvolutions = legalEvolutions(state)
        if pendingEvolutions.isEmpty {
            endHumanTurn()
        } else {
            phase = .evolve
        }
    }

    // MARK: - 진화

    func applyEvolutionChoice(_ e: Evolution) {
        guard phase == .evolve, canApplyEvolution(state, e) else { return }
        applyEvolution(state, e)
        let t = cardOf(e.targetId)
        lastMessage = "\(t.name)(으)로 진화!"
        endHumanTurn()
    }

    func skipEvolution() {
        guard phase == .evolve else { return }
        endHumanTurn()
    }

    private func endHumanTurn() {
        pendingEvolutions = []
        finishTurn(state)
        resolvePhaseForCurrent()
    }

    // MARK: - 턴 흐름 / AI

    /// 현재 플레이어에 맞춰 phase 결정. AI 차례면 구동.
    private func resolvePhaseForCurrent() {
        if state.ended { phase = .gameOver; return }
        if isHumanTurn {
            phase = .main
            // 사람인데 합법 행동이 전혀 없으면(드묾) 강제 패스.
            if legalMainActions(state).isEmpty {
                lastMessage = "행동 불가 — 패스"
                finishTurn(state)
                resolvePhaseForCurrent()
            }
            return
        }
        phase = .aiThinking
        runAITurn()
    }

    private func runAITurn() {
        Task { @MainActor in
            // 시각적 텀(생각 중 표시). 계산은 메인 액터에서 동기 수행(엔진은 릴리스 빌드에서 빠름).
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard phase == .aiThinking, !state.ended else { return }
            if let pick = chooseStrongTurn(state, aiRng) {
                let p = state.currentPlayer
                takeTurn(state, pick.action, pick.evolution)
                lastMessage = "\(playerNames[p]): \(describe(pick.action))"
            } else {
                finishTurn(state)
            }
            resolvePhaseForCurrent()
        }
    }

    // MARK: - 텍스트

    private func describe(_ a: MainAction) -> String {
        switch a {
        case let .take3(colors):
            return "구슬 " + colors.map { COLOR_DISPLAY[BallColor(rawValue: $0.rawValue)!] ?? "" }.joined(separator: "·")
        case let .take2(color):
            return "구슬 " + (COLOR_DISPLAY[BallColor(rawValue: color.rawValue)!] ?? "") + " 2개"
        case let .reserve(cardId):
            return cardOf(cardId).name + " 보관"
        case .reserveBlind:
            return "비공개 보관"
        case let .acquire(cardId, _):
            return cardOf(cardId).name + " 획득"
        }
    }
}
