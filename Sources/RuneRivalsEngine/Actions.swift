// 합법 행동 생성. 현재 플레이어 기준.

import Foundation

public enum MainAction: Equatable {
    case take3(colors: [Color])
    case take2(color: Color)
    case reserve(cardId: String)
    case acquire(cardId: String, pay: [BallColor: Int])
    case reserveBlind(tier: Int)   // 1 | 2 | 3
}

public struct Evolution: Equatable {
    public let sourceId: String
    public let targetId: String
    public init(sourceId: String, targetId: String) {
        self.sourceId = sourceId
        self.targetId = targetId
    }
}

/// combinations: 배열에서 k 개를 고르는 조합.
func combos<T>(_ arr: [T], _ k: Int) -> [[T]] {
    var out: [[T]] = []
    let n = arr.count
    if k > n { return out }
    var idx = Array(0..<k)
    while true {
        out.append(idx.map { arr[$0] })
        var i = k - 1
        while i >= 0 && idx[i] == i + n - k { i -= 1 }
        if i < 0 { break }
        idx[i] += 1
        for j in (i + 1)..<k { idx[j] = idx[j - 1] + 1 }
    }
    return out
}

private func colorToBall(_ c: Color) -> BallColor { BallColor(rawValue: c.rawValue)! }

private func legalTake3(_ s: GameState, _ p: PlayerState) -> [MainAction] {
    let avail = COLORS.filter { (s.supply[colorToBall($0)] ?? 0) > 0 }
    var out: [MainAction] = []
    // 서로 다른 색을 1~3개까지(강제 3개 아님). 최대 = min(3, 남은 색 종류, 손 여유칸).
    let capacity = MAX_BALLS_IN_HAND - handBallCount(p)
    let maxK = min(3, avail.count, capacity)
    if maxK < 1 { return out }
    for k in stride(from: maxK, through: 1, by: -1) {
        for c in combos(avail, k) { out.append(.take3(colors: c)) }
    }
    return out
}

private func legalTake2(_ s: GameState, _ p: PlayerState) -> [MainAction] {
    if !withinBallLimit(p, 2) { return [] }
    var out: [MainAction] = []
    for c in COLORS where (s.supply[colorToBall(c)] ?? 0) >= 4 {
        out.append(.take2(color: c))
    }
    return out
}

private func legalReserve(_ s: GameState, _ p: PlayerState) -> [MainAction] {
    if !canReserveMore(p) { return [] }
    var out: [MainAction] = []
    for t in STAGE_TIERS {
        for id in s.board[.stage(t)] ?? [] { out.append(.reserve(cardId: id)) }
    }
    return out
}

private func legalReserveBlind(_ s: GameState, _ p: PlayerState) -> [MainAction] {
    if !canReserveMore(p) { return [] }
    var out: [MainAction] = []
    for t in STAGE_TIERS where !(s.decks[.stage(t)] ?? []).isEmpty {
        out.append(.reserveBlind(tier: t))
    }
    return out
}

/// 카드 획득 정규 지불(컬러 우선, 부족분 gold). 불가 시 nil.
public func computePay(_ p: PlayerState, _ card: CardDef) -> [BallColor: Int]? {
    let cost = discountedCost(card, p.bonus)
    var pay: [BallColor: Int] = [.red: 0, .blue: 0, .black: 0, .pink: 0, .yellow: 0, .gold: 0]
    var goldShort = 0
    for c in COLORS {
        let req = cost[c] ?? 0
        let use = min(req, p.balls[colorToBall(c)] ?? 0)
        pay[colorToBall(c)] = use
        goldShort += req - use
    }
    if isNoble(card.tier) { goldShort += 1 }
    if (p.balls[.gold] ?? 0) < goldShort { return nil }
    pay[.gold] = goldShort
    return pay
}

private func legalAcquire(_ s: GameState, _ p: PlayerState) -> [MainAction] {
    var out: [MainAction] = []
    var candidates: [String] = boardCardIds(s)
    candidates.append(contentsOf: p.reserved)
    for id in candidates {
        let card = cardOf(id)
        if !canAfford(p, card) { continue }
        guard let pay = computePay(p, card) else { continue }
        out.append(.acquire(cardId: id, pay: pay))
    }
    return out
}

public func legalMainActions(_ s: GameState) -> [MainAction] {
    if s.ended { return [] }
    let p = s.players[s.currentPlayer]
    var out: [MainAction] = []
    out.append(contentsOf: legalTake3(s, p))
    out.append(contentsOf: legalTake2(s, p))
    out.append(contentsOf: legalReserve(s, p))
    out.append(contentsOf: legalReserveBlind(s, p))
    out.append(contentsOf: legalAcquire(s, p))
    return out
}

/// 진화 후보(턴당 1회). source=내 타일 카드, target=보관 or 보드. targetId 기준 중복제거.
public func legalEvolutions(_ s: GameState) -> [Evolution] {
    if s.ended || s.evolvedThisTurn { return [] }
    let p = s.players[s.currentPlayer]
    var out: [Evolution] = []
    var seen = Set<String>()
    for sourceId in p.scored {
        let source = cardOf(sourceId)
        guard let evolvesTo = source.evolvesTo, let evoCost = source.evoCost else { continue }
        var ok = true
        for c in COLORS where (evoCost[c] ?? 0) > (p.bonus[c] ?? 0) { ok = false; break }
        if !ok { continue }
        // 보관 중
        for rid in p.reserved where cardOf(rid).romanized == evolvesTo && !seen.contains(rid) {
            seen.insert(rid)
            out.append(Evolution(sourceId: sourceId, targetId: rid))
        }
        // 보드
        for id in boardCardIds(s) where cardOf(id).romanized == evolvesTo && !seen.contains(id) {
            seen.insert(id)
            out.append(Evolution(sourceId: sourceId, targetId: id))
        }
    }
    return out
}
