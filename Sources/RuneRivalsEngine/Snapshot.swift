// 온라인 동기화용 게임 상태 스냅샷(Codable, JSON).
// 호스트(좌석 0)가 규칙을 처리하고 매 턴 이 스냅샷을 broadcast → 참가자/관전자는 렌더만.
// 딕셔너리는 JSON 호환을 위해 rawValue(String) 키의 [String:Int] 로 표현한다.
// tier 키: "1" "2" "3" "rare" "legendary".

import Foundation

public func tierKey(_ t: Tier) -> String {
    switch t {
    case .stage(let n): return String(n)
    case .rare: return "rare"
    case .legendary: return "legendary"
    }
}

public func tierFromKey(_ k: String) -> Tier {
    switch k {
    case "rare": return .rare
    case "legendary": return .legendary
    default: return .stage(Int(k) ?? 1)
    }
}

public struct PlayerSnapshot: Codable, Sendable {
    public var id: Int
    public var isHuman: Bool
    public var balls: [String: Int]
    public var bonus: [String: Int]
    public var reserved: [String]
    public var scored: [String]
    public var evolutions: Int
}

public struct GameSnapshot: Codable, Sendable {
    public var numPlayers: Int
    public var supply: [String: Int]
    public var deckCounts: [String: Int]
    public var board: [String: [String]]
    public var players: [PlayerSnapshot]
    public var currentPlayer: Int
    public var startingPlayer: Int
    public var triggeredEnd: Bool
    public var ended: Bool
    public var evolvedThisTurn: Bool

    /// 현재 게임 상태 → 스냅샷.
    public init(from s: GameState) {
        numPlayers = s.numPlayers
        supply = Dictionary(uniqueKeysWithValues: BALL_COLORS.map { ($0.rawValue, s.supply[$0] ?? 0) })
        var dc: [String: Int] = [:]
        var bd: [String: [String]] = [:]
        for t in TIERS {
            dc[tierKey(t)] = (s.decks[t] ?? []).count
            bd[tierKey(t)] = s.board[t] ?? []
        }
        deckCounts = dc
        board = bd
        players = s.players.map { p in
            PlayerSnapshot(
                id: p.id,
                isHuman: p.isHuman,
                balls: Dictionary(uniqueKeysWithValues: BALL_COLORS.map { ($0.rawValue, p.balls[$0] ?? 0) }),
                bonus: Dictionary(uniqueKeysWithValues: COLORS.map { ($0.rawValue, p.bonus[$0] ?? 0) }),
                reserved: p.reserved,
                scored: p.scored,
                evolutions: p.evolutions
            )
        }
        currentPlayer = s.currentPlayer
        startingPlayer = s.startingPlayer
        triggeredEnd = s.triggeredEnd
        ended = s.ended
        evolvedThisTurn = s.evolvedThisTurn
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func decode(_ data: Data) -> GameSnapshot? { try? JSONDecoder().decode(GameSnapshot.self, from: data) }
    public func toJSONString() -> String { String(data: encoded(), encoding: .utf8) ?? "" }
}

public extension GameState {
    /// 스냅샷으로부터 렌더용 상태 재구성(클라이언트). 덱은 개수만 알므로 플레이스홀더 id 로 채운다.
    static func fromSnapshot(_ snap: GameSnapshot, seed: UInt32 = 1) -> GameState {
        let s = createGame(seed: seed, numPlayers: snap.numPlayers, humanIndex: -1)
        s.applySnapshot(snap)
        return s
    }

    /// 기존 상태를 스냅샷에 맞춰 갱신(클라이언트 렌더 동기화).
    func applySnapshot(_ snap: GameSnapshot) {
        for bc in BALL_COLORS { supply[bc] = snap.supply[bc.rawValue] ?? 0 }
        for t in TIERS {
            let k = tierKey(t)
            board[t] = snap.board[k] ?? []
            let n = snap.deckCounts[k] ?? 0
            // 덱 내용은 비공개 — 개수만 유지(placeholder). deckCount 렌더용.
            decks[t] = Array(repeating: "?", count: n)
        }
        for (i, ps) in snap.players.enumerated() where i < players.count {
            let p = players[i]
            p.isHuman = ps.isHuman
            for bc in BALL_COLORS { p.balls[bc] = ps.balls[bc.rawValue] ?? 0 }
            for c in COLORS { p.bonus[c] = ps.bonus[c.rawValue] ?? 0 }
            p.reserved = ps.reserved
            p.scored = ps.scored
            p.evolutions = ps.evolutions
        }
        currentPlayer = snap.currentPlayer
        startingPlayer = snap.startingPlayer
        triggeredEnd = snap.triggeredEnd
        ended = snap.ended
        evolvedThisTurn = snap.evolvedThisTurn
    }
}
