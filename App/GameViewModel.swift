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
    case aiThinking   // AI 차례(온라인에선 "상대 턴 대기"로 재사용)
    case gameOver
}

/// 온라인 대전 컨텍스트. 좌석 0 = 호스트(엔진 권위), 나머지 게스트(스냅샷 렌더 + 액션 전송).
struct OnlineContext {
    let client: RelayClient
    let mySeat: Int
    let isHost: Bool
    var seatOn: [Bool]   // 좌석별 접속 여부(호스트가 roster로 갱신, 끊긴 좌석은 턴 스킵)
}

@MainActor
@Observable
final class GameViewModel {
    private(set) var state: GameState
    let mode: GameMode
    let playerNames: [String]

    private(set) var phase: TurnPhase = .main
    /// 현재 턴 좌석(state.currentPlayer 미러). state 는 class 라 in-place 변경이 관측 안 되므로
    /// VM 의 저장 프로퍼티로 노출 → 턴이 바뀔 때마다(AI→AI 포함) 뷰가 확실히 갱신된다.
    private(set) var currentSeat: Int = 0
    /// 턴당 제한 시간(초).
    static let turnSeconds = 30
    /// 현재 턴 남은 시간(초). 매 턴 turnSeconds 로 리셋, 0 되면 자동 패스.
    private(set) var secondsLeft = 30
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    /// 룬 선택: 색 → 선택 개수(1=서로 다른 색 take3용, 2=같은 색 take2). 탭으로 0→1→2→0 순환.
    private(set) var ballPick: [Color: Int] = [:]
    /// 마지막 로그 메시지(간단 피드백).
    private(set) var lastMessage: String = ""
    /// 진화 후보(evolve 단계).
    private(set) var pendingEvolutions: [Evolution] = []

    private let aiRng: Rng

    /// 온라인 대전 컨텍스트(nil = 싱글/오프라인).
    @ObservationIgnored private(set) var online: OnlineContext?
    @ObservationIgnored private var onlineSeed: UInt32 = 0
    @ObservationIgnored private var resultPosted = false
    var isOnline: Bool { online != nil }
    var mySeat: Int { online?.mySeat ?? 0 }

    init(mode: GameMode, numPlayers: Int, seed: UInt32) {
        self.mode = mode
        self.online = nil
        // 싱글: P0 만 사람, 나머지 AI.
        self.state = createGame(seed: seed, numPlayers: numPlayers, humanIndex: 0)
        self.aiRng = Rng(seed: seed &+ 12321)
        self.playerNames = (0..<numPlayers).map { i in i == 0 ? "나" : "AI \(i)" }
        resolvePhaseForCurrent()
    }

    /// 온라인 일반전 초기화. 호스트=엔진 실행+시드 생성+브로드캐스트, 게스트=start 대기.
    init(online client: RelayClient, seat: Int, isHost: Bool, names: [String]) {
        self.mode = .casual
        self.playerNames = names.isEmpty ? ["P1"] : names
        self.aiRng = Rng(seed: 1)   // 온라인엔 미사용
        let n = (names.isEmpty ? ["P1"] : names).count
        self.online = OnlineContext(client: client, mySeat: seat, isHost: isHost, seatOn: Array(repeating: true, count: n))
        if isHost {
            let seed = UInt32.random(in: 1 ... .max)
            self.onlineSeed = seed
            self.state = createGame(seed: seed, numPlayers: n, humanIndex: seat)
        } else {
            self.state = createGame(seed: 1, numPlayers: n, humanIndex: seat)   // 임시(호스트 start로 교체)
        }
        client.onEvent = { [weak self] ev in
            MainActor.assumeIsolated { self?.handleOnline(ev) }
        }
        if isHost {
            resolvePhaseForCurrent()        // 첫 스냅샷 브로드캐스트 포함
        } else {
            phase = .aiThinking             // 대기
            client.relay(["k": "ready"])    // 호스트에 현재 스냅샷 요청(첫 동기화, 레이스 방지)
        }
    }

    /// 같은 인원으로 새 게임 시작(새 랜덤 시드 → 새 턴 순서).
    func newGame() {
        state = createGame(seed: UInt32.random(in: 1 ... .max), numPlayers: state.numPlayers, humanIndex: 0)
        phase = .main
        ballPick = [:]
        pendingEvolutions = []
        lastMessage = ""
        resolvePhaseForCurrent()
    }

    // MARK: - 조회

    var currentPlayer: PlayerState { state.players[state.currentPlayer] }
    var isHumanTurn: Bool {
        if state.ended { return false }
        return state.currentPlayer == mySeat
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

    /// 이 카드가 해당 플레이어의 블라인드 찜인지 — 상대에겐 앞면 비공개(뒷면=레벨만).
    func isBlindReserved(_ playerIdx: Int, _ cardId: String) -> Bool {
        state.players[playerIdx].blindReserved.contains(cardId)
    }

    // MARK: - 룬 집기 (탭만으로 0→1→2→0 순환)

    /// 이 색이 현재 몇 개 선택됐는지(0/1/2).
    func pickedCount(_ c: Color) -> Int { ballPick[c] ?? 0 }

    /// 표시용: 선택 룬을 개수만큼 펼친 목록.
    var pickedList: [Color] { ballPick.flatMap { c, n in Array(repeating: c, count: n) } }

    /// 같은 색 2개(take2) 모드인지.
    private var isTake2Mode: Bool { ballPick.values.contains(2) }

    /// 룬 탭: 0→1→(같은 색 2개 가능하면 2, 아니면 해제)→0.
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

    /// 찜은 되지만 마스터 룬을 못 받는 상황(손패 10개 꽉 참 or 남은 마스터 룬 0개) → 확인 필요.
    func reserveNeedsConfirm(_ cardId: String) -> Bool {
        guard canReserveCard(cardId) else { return false }
        let handFull = handBallCount(currentPlayer) >= MAX_BALLS_IN_HAND
        let noCoin = supplyCount(.gold) == 0
        return handFull || noCoin
    }

    /// 카드 상세의 '진화': 이 카드를 대상으로 하는 합법 진화가 있으면 가능(턴당 1회).
    func canEvolveInto(_ cardId: String) -> Bool {
        guard isHumanTurn, !state.evolvedThisTurn else { return false }
        switch phase {
        case .main:
            return legalEvolutions(state).contains { $0.targetId == cardId }
        case .evolve:
            return pendingEvolutions.contains { $0.targetId == cardId }
        case .aiThinking, .gameOver:
            return false
        }
    }

    func evolveInto(_ cardId: String) {
        guard canEvolveInto(cardId) else { return }
        if let o = online {
            if o.isHost {
                if phase == .evolve { hostApplyEvolve(cardId) } else { hostEvolveDirect(cardId) }
            } else {
                var p: [String: Any] = ["k": "action"]
                if phase == .evolve { p["evolve"] = cardId } else { p["evolveDirect"] = cardId }
                o.client.relay(p)
            }
            return
        }
        let candidates = phase == .evolve ? pendingEvolutions : legalEvolutions(state)
        guard let e = candidates.first(where: { $0.targetId == cardId }) else { return }
        applyEvolution(state, e)
        lastMessage = "\(cardOf(cardId).name)(으)로 진화!"
        endHumanTurn()
    }

    // MARK: - 메인 액션 실행 → 진화 단계 or 턴 종료

    /// GameState 는 class 라 in-place 변경이 @Observable 에 감지되지 않는다.
    /// 상태 변경 후 state 프로퍼티를 재발행해 상태 기반 뷰(패널·보드·룬 등)를 갱신한다.
    private func publishState() {
        let s = state
        state = s
    }

    private func performMain(_ action: MainAction) {
        guard isHumanTurn, phase == .main, canApplyMainAction(state, action) else { return }
        if let o = online {
            if o.isHost { hostApplyMain(action) }   // 호스트: 로컬 적용 + 브로드캐스트
            else { sendMainIntent(action) }         // 게스트: 의도만 전송(적용은 호스트)
            return
        }
        applyMainAction(state, action)
        publishState()
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
        if let o = online {
            if o.isHost { hostApplyEvolve(e.targetId) }
            else { o.client.relay(["k": "action", "evolve": e.targetId]) }
            return
        }
        applyEvolution(state, e)
        let t = cardOf(e.targetId)
        lastMessage = "\(t.name)(으)로 진화!"
        endHumanTurn()
    }

    func skipEvolution() {
        guard phase == .evolve else { return }
        if let o = online {
            if o.isHost { hostSkipEvolve() }
            else { o.client.relay(["k": "action", "skip": true]) }
            return
        }
        endHumanTurn()
    }

    private func endHumanTurn() {
        pendingEvolutions = []
        finishTurn(state)
        resolvePhaseForCurrent()
    }

    // MARK: - 턴 흐름 / AI

    /// 현재 플레이어에 맞춰 phase 결정. AI 차례면 구동.
    // MARK: - 턴 타이머

    /// 현재 턴 타이머 시작(40초 카운트다운). 매 턴 리셋.
    private func startTurnTimer() {
        timerTask?.cancel()
        SoundPlayer.stop("warn")   // 이전 턴의 경고음(초침)이 남아있으면 끊기
        secondsLeft = Self.turnSeconds
        timerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, !self.state.ended else { return }
                if self.secondsLeft > 0 { self.secondsLeft -= 1 }
                // 10초 남으면 경고음(내 턴에만). App/Sounds/warn.mp3 필요.
                if self.secondsLeft == 10 && self.isHumanTurn { SoundPlayer.play("warn") }
                if self.secondsLeft <= 0 { self.onTurnTimeout(); return }
            }
        }
    }

    private func stopTimer() { timerTask?.cancel(); timerTask = nil; SoundPlayer.stop("warn") }

    /// 시간 초과: 사람 턴이면 자동 패스(진화 단계면 진화 생략). AI 턴이면 무시(이미 빠르게 진행).
    private func onTurnTimeout() {
        guard !state.ended else { return }
        if let o = online {
            guard o.isHost else { return }   // 게스트 타이머는 표시용(호스트가 권위 처리)
            lastMessage = "시간 초과 — 패스"
            if phase == .evolve { hostSkipEvolve() }
            else { finishTurn(state); resolvePhaseForCurrent() }
            return
        }
        if phase == .evolve {
            lastMessage = "시간 초과 — 진화 생략"
            skipEvolution()
        } else if isHumanTurn && phase == .main {
            lastMessage = "시간 초과 — 패스"
            endHumanTurn()
        }
    }

    private func resolvePhaseForCurrent() {
        currentSeat = state.currentPlayer
        publishState()
        if state.ended {
            phase = .gameOver; stopTimer()
            if online?.isHost == true { broadcastSnap(); postResult() }
            return
        }
        if let o = online {
            // 온라인: 호스트만 이 경로로 턴 진행(게스트는 applyOnlineTurnState 로 렌더).
            guard o.isHost else { return }
            broadcastSnap()
            // 끊긴 좌석이면 즉시 스킵(연결된 좌석이 하나도 없으면 대기).
            if o.seatOn.indices.contains(state.currentPlayer), !o.seatOn[state.currentPlayer] {
                if o.seatOn.contains(true) {
                    lastMessage = "\(playerNames[state.currentPlayer]) 이탈 — 스킵"
                    finishTurn(state); resolvePhaseForCurrent()
                }
                return
            }
            startTurnTimer()
            phase = (state.currentPlayer == o.mySeat) ? .main : .aiThinking   // 내 턴 / 상대 턴 대기
            if phase == .main, legalMainActions(state).isEmpty {
                lastMessage = "행동 불가 — 패스"
                finishTurn(state); resolvePhaseForCurrent()
            }
            return
        }
        // 단일(오프라인)
        startTurnTimer()
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
            // 시각적 텀(생각 중 표시) — 5~15초 랜덤으로 여유. 계산 자체는 즉시(딜레이는 타이밍용).
            let delay = Double.random(in: 5 ... 15)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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

    // MARK: - 온라인 (호스트 권위 + 스냅샷 동기화)

    private func handleOnline(_ ev: RelayEvent) {
        switch ev {
        case let .relay(fromSeat, payload):
            handleRelayPayload(fromSeat: fromSeat, payload: payload)
        case let .roster(entries, _):
            guard var o = online else { return }
            var on = Array(repeating: false, count: playerNames.count)
            for e in entries where e.seat >= 0 && e.seat < on.count { on[e.seat] = e.on }
            o.seatOn = on
            online = o
            // 호스트: 현재 좌석이 방금 끊겼으면 스킵 재평가
            if o.isHost, !state.ended, o.seatOn.indices.contains(state.currentPlayer),
               !o.seatOn[state.currentPlayer], o.seatOn.contains(true),
               (phase == .aiThinking || phase == .main) {
                finishTurn(state); resolvePhaseForCurrent()
            }
        case .closed, .hostLeft, .reconnectFail:
            if !state.ended { lastMessage = "연결이 끊겼어요" }
        default:
            break
        }
    }

    private func handleRelayPayload(fromSeat: Int, payload: [String: Any]) {
        guard let o = online, let k = payload["k"] as? String else { return }
        if o.isHost {
            if k == "ready" { broadcastSnap(); return }   // 게스트 첫 동기화 요청
            guard k == "action" else { return }
            applyRemoteAction(seat: fromSeat, payload: payload)
        } else if k == "snap" {
            if let s = payload["snap"] as? String, let snap = GameSnapshot.decode(Data(s.utf8)) {
                state.applySnapshot(snap)
            }
            let seat = payload["seat"] as? Int ?? state.currentPlayer
            let ph = payload["phase"] as? String ?? "main"
            let msg = payload["msg"] as? String ?? ""
            applyOnlineTurnState(seat: seat, phaseStr: ph, msg: msg)
        }
    }

    private func applyRemoteAction(seat: Int, payload: [String: Any]) {
        guard state.currentPlayer == seat, !state.ended else { return }
        if let tgt = payload["evolveDirect"] as? String, phase == .main { hostEvolveDirect(tgt); return }
        if phase == .main, let action = decodeMainIntent(payload) { hostApplyMain(action); return }
        if phase == .evolve {
            if let tgt = payload["evolve"] as? String { hostApplyEvolve(tgt) }
            else if payload["skip"] != nil { hostSkipEvolve() }
        }
    }

    private func decodeMainIntent(_ p: [String: Any]) -> MainAction? {
        if let cols = p["take3"] as? [String] { return .take3(colors: cols.compactMap { Color(rawValue: $0) }) }
        if let c = p["take2"] as? String, let col = Color(rawValue: c) { return .take2(color: col) }
        if let id = p["reserve"] as? String { return .reserve(cardId: id) }
        if let t = p["reserveBlind"] as? Int { return .reserveBlind(tier: t) }
        if let id = p["acquire"] as? String {
            guard let pay = computePay(state.players[state.currentPlayer], cardOf(id)) else { return nil }
            return .acquire(cardId: id, pay: pay)
        }
        return nil
    }

    private func sendMainIntent(_ action: MainAction) {
        guard let o = online else { return }
        var p: [String: Any] = ["k": "action"]
        switch action {
        case let .take3(colors): p["take3"] = colors.map { $0.rawValue }
        case let .take2(color): p["take2"] = color.rawValue
        case let .reserve(id): p["reserve"] = id
        case let .reserveBlind(t): p["reserveBlind"] = t
        case let .acquire(id, _): p["acquire"] = id
        }
        o.client.relay(p)
    }

    // 호스트 권위 적용(현재 좌석의 액션 — 내 좌석/게스트 공통 경로).
    private func hostApplyMain(_ action: MainAction) {
        guard phase == .main, canApplyMainAction(state, action) else { return }
        applyMainAction(state, action)
        ballPick = [:]
        lastMessage = describe(action)
        pendingEvolutions = legalEvolutions(state)
        if pendingEvolutions.isEmpty {
            finishTurn(state); resolvePhaseForCurrent()
        } else {
            phase = .evolve
            broadcastSnap()   // 진화 단계 진입도 게스트에 알림
        }
    }
    private func hostEvolveDirect(_ targetId: String) {
        guard phase == .main, !state.evolvedThisTurn,
              let e = legalEvolutions(state).first(where: { $0.targetId == targetId }) else { return }
        applyEvolution(state, e)
        lastMessage = "\(cardOf(targetId).name)(으)로 진화!"
        finishTurn(state); resolvePhaseForCurrent()
    }
    private func hostApplyEvolve(_ targetId: String) {
        guard phase == .evolve,
              let e = pendingEvolutions.first(where: { $0.targetId == targetId }) else { return }
        applyEvolution(state, e)
        lastMessage = "\(cardOf(targetId).name)(으)로 진화!"
        pendingEvolutions = []
        finishTurn(state); resolvePhaseForCurrent()
    }
    private func hostSkipEvolve() {
        guard phase == .evolve else { return }
        pendingEvolutions = []
        finishTurn(state); resolvePhaseForCurrent()
    }

    /// 호스트: 현재 권위 상태를 전원에 브로드캐스트.
    private func broadcastSnap() {
        guard let o = online, o.isHost else { return }
        let snap = GameSnapshot(from: state).toJSONString()
        let ph = state.ended ? "over" : (phase == .evolve ? "evolve" : "main")
        o.client.relay(["k": "snap", "snap": snap, "seat": state.currentPlayer, "phase": ph, "msg": lastMessage])
    }

    /// 게스트: 호스트 스냅샷에 맞춰 턴 상태 반영.
    private func applyOnlineTurnState(seat: Int, phaseStr: String, msg: String) {
        currentSeat = seat
        if !msg.isEmpty { lastMessage = msg }
        if state.ended || phaseStr == "over" {
            phase = .gameOver; stopTimer(); publishState(); return
        }
        if seat == mySeat {
            phase = (phaseStr == "evolve") ? .evolve : .main
            pendingEvolutions = (phase == .evolve) ? legalEvolutions(state) : []
        } else {
            phase = .aiThinking   // 상대 턴 대기
            pendingEvolutions = []
        }
        startTurnTimer()
        publishState()
    }

    /// 게임 종료 시 호스트만 결과 기록(Supabase 랭킹 + Firebase 히스토리).
    private func postResult() {
        guard let o = online, o.isHost, !resultPosted, state.ended else { return }
        resultPosted = true
        let ranks = rankPlayers(state)   // 순위순 좌석(1등부터)
        var results: [[String: Any]] = []
        for (i, seat) in ranks.enumerated() where seat < state.players.count {
            let p = state.players[seat]
            results.append([
                "seat": seat, "name": playerNames[seat],
                "points": playerPoints(p), "evolutions": p.evolutions,
                "cards": p.scored.count, "rank": i + 1, "isAI": false,
            ])
        }
        let body: [String: Any] = [
            "matchId": UUID().uuidString, "mode": "casual",
            "seed": Int(onlineSeed), "numPlayers": playerNames.count,
            "winnerSeat": winnerId(state) ?? ranks.first ?? 0,
            "results": results,
        ]
        let base = RelayConfig.defaultURL.absoluteString
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")
        guard let url = URL(string: base + "/result"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - 텍스트

    private func describe(_ a: MainAction) -> String {
        switch a {
        case let .take3(colors):
            return "룬 " + colors.map { COLOR_DISPLAY[BallColor(rawValue: $0.rawValue)!] ?? "" }.joined(separator: "·")
        case let .take2(color):
            return "룬 " + (COLOR_DISPLAY[BallColor(rawValue: color.rawValue)!] ?? "") + " 2개"
        case let .reserve(cardId):
            return cardOf(cardId).name + " 보관"
        case .reserveBlind:
            return "비공개 보관"
        case let .acquire(cardId, _):
            return cardOf(cardId).name + " 획득"
        }
    }
}
