// 게임 상태 모델 + 팩토리 + 조회 헬퍼.
// 상태는 가변(class). AI 미리보기는 cloneGame 으로 복제 후 분기한다.

import Foundation

public final class PlayerState {
    public let id: Int
    public var isHuman: Bool
    /// 보유 룬(컬러 5색 + gold).
    public var balls: [BallColor: Int]
    /// 누적 컬러 보너스. 획득 시 증가, 진화 시 불변, 감소 없음.
    public var bonus: [Color: Int]
    /// 보관(예약) 카드 id. 최대 MAX_RESERVED.
    public var reserved: [String]
    /// 블라인드(덱에서 안 보고) 찜한 카드 id — 상대에게 앞면 비공개(뒷면=레벨만).
    public var blindReserved: Set<String> = []
    /// 타일 위 점수 카드 id(진화 시 하위는 제거·상위 추가).
    public var scored: [String]
    /// 진화 횟수(tie-breaker 1순위).
    public var evolutions: Int

    public init(id: Int, isHuman: Bool) {
        self.id = id
        self.isHuman = isHuman
        self.balls = emptyBallMap()
        self.bonus = emptyColorMap()
        self.reserved = []
        self.scored = []
        self.evolutions = 0
    }

    fileprivate init(copy p: PlayerState) {
        id = p.id
        isHuman = p.isHuman
        balls = p.balls
        bonus = p.bonus
        reserved = p.reserved
        blindReserved = p.blindReserved
        scored = p.scored
        evolutions = p.evolutions
    }
}

public final class GameState {
    public let rng: Rng
    public let numPlayers: Int
    public var supply: [BallColor: Int]
    /// 단계별 남은 덱(top = 배열 끝).
    public var decks: [Tier: [String]]
    /// 공개 카드(stage: 최대 REVEAL_PER_STAGE, rare/legendary: 최대 1).
    public var board: [Tier: [String]]
    public var players: [PlayerState]
    public var currentPlayer: Int
    public var startingPlayer: Int
    /// 턴 진행 순서(플레이어 인덱스 순열). 게임 시작 시 랜덤 결정. startingPlayer = turnOrder[0].
    public var turnOrder: [Int]
    /// 누군가 18점 도달 → 현재 라운드 종료 시 게임 종료.
    public var triggeredEnd: Bool
    public var ended: Bool
    /// 이번 턴 진화 사용 여부(턴당 1회).
    public var evolvedThisTurn: Bool

    init(rng: Rng, numPlayers: Int, supply: [BallColor: Int],
         decks: [Tier: [String]], board: [Tier: [String]], players: [PlayerState],
         currentPlayer: Int, startingPlayer: Int, turnOrder: [Int],
         triggeredEnd: Bool, ended: Bool, evolvedThisTurn: Bool) {
        self.rng = rng
        self.numPlayers = numPlayers
        self.supply = supply
        self.decks = decks
        self.board = board
        self.players = players
        self.currentPlayer = currentPlayer
        self.startingPlayer = startingPlayer
        self.turnOrder = turnOrder
        self.triggeredEnd = triggeredEnd
        self.ended = ended
        self.evolvedThisTurn = evolvedThisTurn
    }
}

public func emptyBallMap() -> [BallColor: Int] {
    [.red: 0, .blue: 0, .black: 0, .pink: 0, .yellow: 0, .gold: 0]
}

public func emptyColorMap() -> [Color: Int] {
    [.red: 0, .blue: 0, .black: 0, .pink: 0, .yellow: 0]
}

public func cardOf(_ id: String) -> CardDef {
    guard let c = CARDS_BY_ID[id] else { fatalError("unknown card id: \(id)") }
    return c
}

/// 보유 볼 총합(컬러 + 마스터). 10 한도 검사용.
public func handBallCount(_ p: PlayerState) -> Int {
    var n = 0
    for c in COLORS { n += p.balls[BallColor(rawValue: c.rawValue)!, default: 0] }
    return n + p.balls[.gold, default: 0]
}

/// 할인 후 비용(컬러별). 보너스가 초과해도 0 이하로 내려가지 않는다.
public func discountedCost(_ card: CardDef, _ bonus: [Color: Int]) -> [Color: Int] {
    var out: [Color: Int] = [:]
    for c in COLORS {
        let raw = card.cost[c] ?? 0
        let after = max(0, raw - (bonus[c] ?? 0))
        if after > 0 { out[c] = after }
    }
    return out
}

/// 컬러별 요구량에 대해, 부족분을 gold 로 보충해야 하는 개수.
public func goldNeeded(_ cost: [Color: Int], _ p: PlayerState) -> Int {
    var need = 0
    for c in COLORS {
        let req = cost[c] ?? 0
        let have = p.balls[BallColor(rawValue: c.rawValue)!, default: 0]
        if req > have { need += req - have }
    }
    return need
}

/// 플레이어가 카드를 획득 가능한지(비용 관점). 희귀/전설은 gold 1개 추가 필요.
public func canAfford(_ p: PlayerState, _ card: CardDef) -> Bool {
    let cost = discountedCost(card, p.bonus)
    var gold = goldNeeded(cost, p)
    if isNoble(card.tier) { gold += 1 }
    return p.balls[.gold, default: 0] >= gold
}

/// 플레이어 점수 = 타일 위(scored) 카드 점수 합.
public func playerPoints(_ p: PlayerState) -> Int {
    var n = 0
    for id in p.scored { n += cardOf(id).points }
    return n
}

/// 보드 전체 카드 id 순회(legal action 탐색용). TIERS 순서 유지.
public func boardCardIds(_ s: GameState) -> [String] {
    var out: [String] = []
    for t in TIERS { out.append(contentsOf: s.board[t] ?? []) }
    return out
}

/// 특정 tier 보드에서 해당 id 의 인덱스. 없으면 -1.
public func boardIndex(_ s: GameState, _ tier: Tier, _ id: String) -> Int {
    (s.board[tier] ?? []).firstIndex(of: id) ?? -1
}

private func reveal(_ state: GameState, _ tier: Tier, _ n: Int) {
    var deck = state.decks[tier] ?? []
    var board = state.board[tier] ?? []
    var i = 0
    while i < n && !deck.isEmpty {
        board.append(deck.removeLast())
        i += 1
    }
    state.decks[tier] = deck
    state.board[tier] = board
}

public func createGame(seed: UInt32, numPlayers: Int = 3, humanIndex: Int = 0) -> GameState {
    let rng = Rng(seed: seed)
    var decks: [Tier: [String]] = [:]
    var board: [Tier: [String]] = [:]
    for t in TIERS {
        decks[t] = rng.shuffle(deckOf(t).map { $0.id })
        board[t] = []
    }
    var players: [PlayerState] = []
    for i in 0..<numPlayers {
        players.append(PlayerState(id: i, isHuman: i == humanIndex))
    }
    // 인원수별 시작 칩 조정(최대 3인): 3인 -2, 2인 -3. gold(마스터 룬)는 제외.
    let cut = numPlayers <= 2 ? 3 : (numPlayers == 3 ? 2 : 0)
    var supply = INITIAL_BALL_SUPPLY
    for c in [BallColor.red, .blue, .black, .pink, .yellow] {
        supply[c] = max(0, (INITIAL_BALL_SUPPLY[c] ?? 0) - cut)
    }

    // 턴 순서 랜덤 결정(플레이어 인덱스 순열). 첫 플레이어 = turnOrder[0].
    let turnOrder = rng.shuffle(Array(0..<numPlayers))
    let firstPlayer = turnOrder[0]
    let state = GameState(
        rng: rng, numPlayers: numPlayers, supply: supply, decks: decks, board: board,
        players: players, currentPlayer: firstPlayer, startingPlayer: firstPlayer, turnOrder: turnOrder,
        triggeredEnd: false, ended: false, evolvedThisTurn: false
    )
    for t in STAGE_TIERS { reveal(state, .stage(t), REVEAL_PER_STAGE) }
    reveal(state, .rare, 1)
    reveal(state, .legendary, 1)
    return state
}

/// 깊은 복제(AI 미리보기용). RNG 도 독립 복제.
public func cloneGame(_ s: GameState) -> GameState {
    var decks: [Tier: [String]] = [:]
    var board: [Tier: [String]] = [:]
    for t in TIERS {
        decks[t] = s.decks[t]
        board[t] = s.board[t]
    }
    let players = s.players.map { PlayerState(copy: $0) }
    return GameState(
        rng: s.rng.clone(), numPlayers: s.numPlayers, supply: s.supply,
        decks: decks, board: board, players: players,
        currentPlayer: s.currentPlayer, startingPlayer: s.startingPlayer, turnOrder: s.turnOrder,
        triggeredEnd: s.triggeredEnd, ended: s.ended, evolvedThisTurn: s.evolvedThisTurn
    )
}

/// 보드에서 카드 제거 후 덱에서 보충. 위치 유지(슬롯 제자리 교체).
public func refillBoard(_ state: GameState, _ tier: Tier, _ id: String) {
    var arr = state.board[tier] ?? []
    guard let idx = arr.firstIndex(of: id) else { return }
    var deck = state.decks[tier] ?? []
    if !deck.isEmpty {
        arr[idx] = deck.removeLast()
    } else {
        arr.remove(at: idx)
    }
    state.board[tier] = arr
    state.decks[tier] = deck
}

/// 최대 보관 가능 여부.
public func canReserveMore(_ p: PlayerState) -> Bool {
    p.reserved.count < MAX_RESERVED
}

/// 핸드 볼 한도.
public func withinBallLimit(_ p: PlayerState, _ add: Int) -> Bool {
    handBallCount(p) + add <= MAX_BALLS_IN_HAND
}
