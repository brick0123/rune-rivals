// 규칙 엔진: 행동 적용, 보드 보충, 종료 감지, 승자 판정.

import Foundation

public let WIN_THRESHOLD = 18

private func colorToBall(_ c: Color) -> BallColor { BallColor(rawValue: c.rawValue)! }

private func sameColorSet(_ a: [Color], _ b: [Color]) -> Bool {
    a.count == b.count && a.sorted { $0.rawValue < $1.rawValue } == b.sorted { $0.rawValue < $1.rawValue }
}

private func samePay(_ a: [BallColor: Int], _ b: [BallColor: Int]) -> Bool {
    BALL_COLORS.allSatisfy { (a[$0] ?? 0) == (b[$0] ?? 0) }
}

private func sameMainAction(_ a: MainAction, _ b: MainAction) -> Bool {
    switch (a, b) {
    case let (.take3(ca), .take3(cb)): return sameColorSet(ca, cb)
    case let (.take2(ca), .take2(cb)): return ca == cb
    case let (.reserve(ia), .reserve(ib)): return ia == ib
    case let (.reserveBlind(ta), .reserveBlind(tb)): return ta == tb
    case let (.acquire(ia, pa), .acquire(ib, pb)): return ia == ib && samePay(pa, pb)
    default: return false
    }
}

public func canApplyMainAction(_ s: GameState, _ a: MainAction) -> Bool {
    legalMainActions(s).contains { sameMainAction(a, $0) }
}

public func canApplyEvolution(_ s: GameState, _ e: Evolution) -> Bool {
    legalEvolutions(s).contains { $0.sourceId == e.sourceId && $0.targetId == e.targetId }
}

private func gainBalls(_ s: GameState, _ p: PlayerState, _ color: BallColor, _ n: Int) {
    s.supply[color, default: 0] -= n
    p.balls[color, default: 0] += n
}

private func applyTake3(_ s: GameState, _ colors: [Color]) {
    let p = s.players[s.currentPlayer]
    for c in colors { gainBalls(s, p, colorToBall(c), 1) }
}

private func applyTake2(_ s: GameState, _ color: Color) {
    let p = s.players[s.currentPlayer]
    gainBalls(s, p, colorToBall(color), 2)
}

private func tryGainMaster(_ s: GameState, _ p: PlayerState) {
    if (s.supply[.gold] ?? 0) > 0 && withinBallLimit(p, 1) {
        s.supply[.gold, default: 0] -= 1
        p.balls[.gold, default: 0] += 1
    }
}

private func applyReserve(_ s: GameState, _ cardId: String) {
    let p = s.players[s.currentPlayer]
    let card = cardOf(cardId)
    refillBoard(s, card.tier, cardId)
    p.reserved.append(cardId)
    tryGainMaster(s, p)
}

private func applyReserveBlind(_ s: GameState, _ tier: Int) {
    let p = s.players[s.currentPlayer]
    var deck = s.decks[.stage(tier)] ?? []
    if let id = deck.popLast() {
        p.reserved.append(id)
        p.blindReserved.insert(id)   // 블라인드 = 상대 비공개
        s.decks[.stage(tier)] = deck
    }
    tryGainMaster(s, p)
}

private func applyAcquire(_ s: GameState, _ cardId: String, _ pay: [BallColor: Int]) {
    let p = s.players[s.currentPlayer]
    let card = cardOf(cardId)
    // 지불
    for c in COLORS {
        let bc = colorToBall(c)
        let amt = pay[bc] ?? 0
        if amt > 0 {
            s.supply[bc, default: 0] += amt
            p.balls[bc, default: 0] -= amt
        }
    }
    let goldPay = pay[.gold] ?? 0
    if goldPay > 0 {
        s.supply[.gold, default: 0] += goldPay
        p.balls[.gold, default: 0] -= goldPay
    }
    // 출처 제거
    if let ridx = p.reserved.firstIndex(of: cardId) {
        p.reserved.remove(at: ridx)
        p.blindReserved.remove(cardId)
    } else {
        refillBoard(s, card.tier, cardId)
    }
    // 타일에 적재 + 보너스 누적
    p.scored.append(cardId)
    for c in COLORS {
        let b = card.bonus[c] ?? 0
        if b > 0 { p.bonus[c, default: 0] += b }
    }
}

public func applyMainAction(_ s: GameState, _ a: MainAction) {
    precondition(canApplyMainAction(s, a), "illegal main action")
    switch a {
    case let .take3(colors): applyTake3(s, colors)
    case let .take2(color): applyTake2(s, color)
    case let .reserve(cardId): applyReserve(s, cardId)
    case let .reserveBlind(tier): applyReserveBlind(s, tier)
    case let .acquire(cardId, pay): applyAcquire(s, cardId, pay)
    }
}

public func applyEvolution(_ s: GameState, _ e: Evolution) {
    precondition(canApplyEvolution(s, e), "illegal evolution")
    let p = s.players[s.currentPlayer]
    let target = cardOf(e.targetId)
    // source 타일 아래로(점수 제거, 보너스는 불변으로 유지)
    if let sidx = p.scored.firstIndex(of: e.sourceId) { p.scored.remove(at: sidx) }
    // target 출처 제거
    if let ridx = p.reserved.firstIndex(of: e.targetId) {
        p.reserved.remove(at: ridx)
        p.blindReserved.remove(e.targetId)
    } else {
        refillBoard(s, target.tier, e.targetId)
    }
    // target 타일 적재. 보너스는 진화 시 증가 없음(하위 보너스가 이미 누적되어 유지됨).
    p.scored.append(e.targetId)
    p.evolutions += 1
    s.evolvedThisTurn = true
}

/// 턴 종료: 18점 임계점 체크, 진화 플래그 리셋, 다음 플레이어로, 종료 감지.
public func finishTurn(_ s: GameState) {
    let justPlayed = s.currentPlayer
    if playerPoints(s.players[justPlayed]) >= WIN_THRESHOLD { s.triggeredEnd = true }
    s.evolvedThisTurn = false
    // turnOrder(랜덤 순열) 기준으로 다음 플레이어. 첫 플레이어로 되돌아오면 라운드 종료.
    let pos = s.turnOrder.firstIndex(of: s.currentPlayer) ?? 0
    let next = s.turnOrder[(pos + 1) % s.numPlayers]
    s.currentPlayer = next
    if s.triggeredEnd && next == s.startingPlayer { s.ended = true }
}

/// 플레이어 순위 배열(내림차순). tie-breaker: 점수 → 진화 수 → 획득 카드 수.
public func rankPlayers(_ s: GameState) -> [Int] {
    let order = s.players.map { p -> (id: Int, pts: Int, evo: Int, cards: Int) in
        (p.id, playerPoints(p), p.evolutions, p.scored.count)
    }.sorted { a, b in
        if a.pts != b.pts { return a.pts > b.pts }
        if a.evo != b.evo { return a.evo > b.evo }
        return a.cards > b.cards
    }
    return order.map { $0.id }
}

/// 1위 플레이어 id.
public func winnerId(_ s: GameState) -> Int {
    rankPlayers(s)[0]
}

/// 메인 액션 + (선택)진화 + 턴 종료까지 한 번에 수행.
public func takeTurn(_ s: GameState, _ action: MainAction, _ evolution: Evolution?) {
    applyMainAction(s, action)
    if let e = evolution { applyEvolution(s, e) }
    finishTurn(s)
}

/// 합법 행동이 없는 경우(볼 한도·자원 고갈) → 강제 패스. 드문 예외.
public func hasAnyAction(_ s: GameState) -> Bool {
    !legalMainActions(s).isEmpty
}
