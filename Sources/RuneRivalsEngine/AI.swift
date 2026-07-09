// AI 의사결정 정책. 3층: 팩트→평가함수→행동규칙.
// chooseTurn = 경량 정책(플레이아웃용). chooseStrongTurn = 실제 AI 턴용 후보 탐색 정책.

import Foundation

/// 진화 테크 색상 집합. 메인 3색 + 서브 집합.
private let TECH_SETS: [[Color]] = [
    [.blue, .yellow, .red],
    [.yellow, .pink, .blue],
    [.red, .black, .pink],
    [.black, .blue, .yellow],
    [.blue, .pink, .black],
    [.yellow, .black, .red],
    [.blue, .red],
    [.yellow, .blue],
    [.red, .pink],
    [.pink, .black],
    [.black, .yellow],
]

/// 카드의 라인 색(보너스 단일 키).
private func lineColorOf(_ card: CardDef) -> Color? {
    card.bonus.keys.first
}

/// 카드가 현재 플레이어의 진화 경로상 다음 단계인지.
private func isNextEvoStep(_ p: PlayerState, _ card: CardDef) -> Bool {
    p.scored.contains { cardOf($0).evolvesTo == card.romanized }
}

/// 목표 색상 집합: 현재 보유·보드와 가장 정렬된 테크. 매 턴 재산출.
public func goalSet(_ state: GameState, _ p: PlayerState) -> [Color] {
    var best = TECH_SETS[0]
    var bestScore = -Double.infinity
    for set in TECH_SETS {
        var score = 0.0
        func inset(_ c: Color) -> Bool { set.contains(c) }
        for sid in p.scored {
            if let lc = lineColorOf(cardOf(sid)), inset(lc) { score += 2.5 }
        }
        for rid in p.reserved {
            if let lc = lineColorOf(cardOf(rid)), inset(lc) { score += 1.5 }
        }
        for c in COLORS where inset(c) { score += Double(p.bonus[c] ?? 0) * 0.8 }
        for t in TIERS {
            for id in state.board[t] ?? [] {
                if let lc = lineColorOf(cardOf(id)), inset(lc) { score += 0.4 }
            }
        }
        if score > bestScore { bestScore = score; best = set }
    }
    return best
}

/// 볼 1개의 가치(목표 정렬 + 타겟 카드 비용 충족 기여).
private func ballValue(_ state: GameState, _ p: PlayerState, _ c: Color, _ goal: [Color]) -> Double {
    var v = goal.contains(c) ? 0.55 : 0.04
    for t in [Tier.stage(2), .stage(3)] {
        for id in state.board[t] ?? [] {
            let card = cardOf(id)
            guard let lc = lineColorOf(card), goal.contains(lc) else { continue }
            let need = max(0, (card.cost[c] ?? 0) - (p.bonus[c] ?? 0))
            let short = max(0, need - (p.balls[BallColor(rawValue: c.rawValue)!] ?? 0))
            v += Double(short) * 0.12 * (Double(card.points) / 5.0)
        }
    }
    v *= 1.0 / (1.0 + Double(p.balls[BallColor(rawValue: c.rawValue)!] ?? 0) * 0.12)
    return v
}

/// V_card.
public func cardValue(_ p: PlayerState, _ card: CardDef, _ goal: [Color]) -> Double {
    var v = WEIGHTS.pts * Double(card.points)
    for col in COLORS {
        let n = card.bonus[col] ?? 0
        if n <= 0 { continue }
        let marginal = goal.contains(col) ? 1.0 : 0.3
        let diminishing = 1.0 / (1.0 + Double(p.bonus[col] ?? 0) * 0.5)
        v += WEIGHTS.bonus * Double(n) * marginal * diminishing
    }
    if isNextEvoStep(p, card) { v += WEIGHTS.evo }
    if let lc = lineColorOf(card), goal.contains(lc) { v += WEIGHTS.goal }
    let cost = discountedCost(card, p.bonus)
    var costTotal = 0
    for c in COLORS { costTotal += cost[c] ?? 0 }
    if isNoble(card.tier) { costTotal += 1 }
    v -= WEIGHTS.cost * Double(costTotal) * 0.22
    return v
}

private func gainsMaster(_ state: GameState, _ p: PlayerState) -> Bool {
    var total = 0
    for bc in BALL_COLORS { total += p.balls[bc] ?? 0 }
    return (state.supply[.gold] ?? 0) > 0 && total < 10
}

/// 행동 가치.
public func actionValue(_ state: GameState, _ p: PlayerState, _ action: MainAction, _ goal: [Color]) -> Double {
    switch action {
    case let .acquire(cardId, pay):
        let card = cardOf(cardId)
        var v = cardValue(p, card, goal)
        v -= Double(pay[.gold] ?? 0) * 0.12
        return v
    case let .reserve(cardId):
        let card = cardOf(cardId)
        var v = cardValue(p, card, goal) * WEIGHTS.reserve
        if gainsMaster(state, p) { v += WEIGHTS.master }
        return v
    case let .reserveBlind(tier):
        let tierVal = tier == 3 ? 1.0 : (tier == 2 ? 0.7 : 0.4)
        var v = WEIGHTS.blind * tierVal
        if gainsMaster(state, p) { v += WEIGHTS.master }
        return v
    case let .take3(colors):
        var v = 0.0
        for c in colors { v += ballValue(state, p, c, goal) }
        return v
    case let .take2(color):
        return ballValue(state, p, color, goal) * 2 + 0.18
    }
}

/// V_evolve = 상위점수 − 하위점수 + tiebreak.
private func evolutionValue(_ source: CardDef, _ target: CardDef) -> Double {
    Double(target.points - source.points) + WEIGHTS.tiebreak
}

/// 최적 진화(V_evolve 최대, 양수일 때만).
public func bestEvolution(_ state: GameState) -> Evolution? {
    let evos = legalEvolutions(state)
    if evos.isEmpty { return nil }
    var best: Evolution? = nil
    var bestV = 0.0
    for e in evos {
        let v = evolutionValue(cardOf(e.sourceId), cardOf(e.targetId))
        if v > bestV { bestV = v; best = e }
    }
    return best
}

private func softmaxPick(_ scores: [Double], _ rng: Rng) -> Int {
    let top = scores.enumerated()
        .map { (i: $0.offset, s: $0.element) }
        .sorted { $0.s > $1.s }
        .prefix(min(USER_TOP_K, scores.count))
    let arr = Array(top)
    let mx = arr.map { $0.s }.max() ?? 0
    let exps = arr.map { exp(($0.s - mx) / USER_SOFTMAX_TEMP) }
    let sum = exps.reduce(0, +)
    var r = rng.next() * sum
    for k in 0..<arr.count {
        r -= exps[k]
        if r <= 0 { return arr[k].i }
    }
    return arr[arr.count - 1].i
}

public enum PolicyMode { case ai, user }

/// 한 턴의 행동+진화 선택. ai=argmax, user=소프트.
public func chooseTurn(_ state: GameState, _ mode: PolicyMode, _ rng: Rng) -> (action: MainAction, evolution: Evolution?)? {
    let p = state.players[state.currentPlayer]
    let actions = legalMainActions(state)
    if actions.isEmpty { return nil }
    let goal = goalSet(state, p)
    let scores = actions.map { actionValue(state, p, $0, goal) }
    let idx: Int
    if mode == .ai {
        idx = scores.firstIndex(of: scores.max()!)!
    } else {
        idx = softmaxPick(scores, rng)
    }
    let action = actions[idx]
    let preview = cloneGame(state)
    applyMainAction(preview, action)
    let evolution = bestEvolution(preview)
    return (action, evolution)
}

private func legalMainActionsForPlayer(_ state: GameState, _ playerIndex: Int) -> [MainAction] {
    let oldCurrent = state.currentPlayer
    let oldEvolved = state.evolvedThisTurn
    state.currentPlayer = playerIndex
    state.evolvedThisTurn = false
    defer {
        state.currentPlayer = oldCurrent
        state.evolvedThisTurn = oldEvolved
    }
    return legalMainActions(state)
}

private func cardPressure(_ player: PlayerState, _ card: CardDef) -> Double {
    var v = Double(card.points) * 3
    var rawNeed = 0
    for c in COLORS {
        let bonus = card.bonus[c] ?? 0
        if bonus > 0 {
            v += Double(bonus) * 1.3
            rawNeed += max(0, (card.cost[c] ?? 0) - (player.bonus[c] ?? 0))
        }
    }
    let cost = discountedCost(card, player.bonus)
    var missing = 0
    for c in COLORS { missing += max(0, (cost[c] ?? 0) - (player.balls[BallColor(rawValue: c.rawValue)!] ?? 0)) }
    if isNoble(card.tier) && (player.balls[.gold] ?? 0) < 1 { missing += 1 }
    if isNextEvoStep(player, card) { v += 2.8 }
    return v - Double(max(0, missing)) * 0.75 - Double(max(0, rawNeed)) * 0.08
}

private func playerEval(_ state: GameState, _ playerIndex: Int) -> Double {
    let player = state.players[playerIndex]
    var v = Double(playerPoints(player)) * 11 + Double(player.evolutions) * 2.2 + Double(player.scored.count) * 0.18
    for c in COLORS {
        v += Double(player.bonus[c] ?? 0) * 1.35 + Double(player.balls[BallColor(rawValue: c.rawValue)!] ?? 0) * 0.16
    }
    v += Double(player.balls[.gold] ?? 0) * 0.75
    for id in player.reserved { v += cardPressure(player, cardOf(id)) * 0.3 }

    var tempo = 0.0
    for action in legalMainActionsForPlayer(state, playerIndex) {
        if case let .acquire(cardId, _) = action {
            let card = cardOf(cardId)
            tempo = max(tempo, cardPressure(player, card) + (card.points >= 3 ? 1.2 : 0))
        } else if case let .reserve(cardId) = action {
            tempo = max(tempo, cardPressure(player, cardOf(cardId)) * 0.28)
        }
    }
    return v + tempo * 0.65
}

private func stateEval(_ state: GameState, _ playerIndex: Int) -> Double {
    let player = state.players[playerIndex]
    let points = playerPoints(player)
    if state.ended {
        let rank = rankPlayers(state).firstIndex(of: playerIndex) ?? 0
        let won = winnerId(state) == playerIndex ? 1.0 : 0.0
        return won * 20_000 - Double(rank) * 3_500 + Double(points) * 80 + Double(player.evolutions) * 25
    }

    let mine = playerEval(state, playerIndex)
    var strongestOpponent = -Double.infinity
    var bestOpponentPoints = 0
    for opponent in state.players {
        if opponent.id == playerIndex { continue }
        strongestOpponent = max(strongestOpponent, playerEval(state, opponent.id))
        bestOpponentPoints = max(bestOpponentPoints, playerPoints(opponent))
    }

    let rank = rankPlayers(state).firstIndex(of: playerIndex) ?? 0
    var v = mine - strongestOpponent + Double(points - bestOpponentPoints) * 8 + Double(3 - rank) * 1.4
    if points >= 15 { v += Double(points - 14) * 8 }
    if points >= WIN_THRESHOLD { v += 450 }
    if bestOpponentPoints >= WIN_THRESHOLD { v -= 520 }
    return v
}

private func blockValue(_ state: GameState, _ playerIndex: Int, _ action: MainAction) -> Double {
    let cardId: String
    switch action {
    case let .reserve(id): cardId = id
    case let .acquire(id, _): cardId = id
    default: return 0
    }
    if !boardCardIds(state).contains(cardId) { return 0 }

    let card = cardOf(cardId)
    var best = 0.0
    for opponent in state.players {
        if opponent.id == playerIndex { continue }
        let canOpponentAcquire = legalMainActionsForPlayer(state, opponent.id).contains { candidate in
            if case let .acquire(id, _) = candidate { return id == cardId }
            return false
        }
        if !canOpponentAcquire { continue }

        var v = Double(card.points) * 4 + 1.8
        if isNextEvoStep(opponent, card) { v += 3 }
        if isNoble(card.tier) { v += 2 }
        if playerPoints(opponent) >= 12 { v += Double(card.points) * 1.5 }
        best = max(best, v)
    }
    return best
}

private func applyCandidate(_ state: GameState, _ action: MainAction) -> (state: GameState, evolution: Evolution?) {
    let preview = cloneGame(state)
    applyMainAction(preview, action)
    let evolution = bestEvolution(preview)
    if let e = evolution { applyEvolution(preview, e) }
    return (preview, evolution)
}

private func chooseGreedyTurn(_ state: GameState) -> (action: MainAction, evolution: Evolution?)? {
    let player = state.players[state.currentPlayer]
    let actions = legalMainActions(state)
    if actions.isEmpty { return nil }

    let goal = goalSet(state, player)
    var bestAction = actions[0]
    var bestScore = -Double.infinity
    for action in actions {
        var score = actionValue(state, player, action, goal) + blockValue(state, state.currentPlayer, action) * 0.25
        if case let .acquire(cardId, _) = action {
            let card = cardOf(cardId)
            score += Double(card.points) * 0.9
            if isNextEvoStep(player, card) { score += 1.4 }
            if playerPoints(player) + card.points >= WIN_THRESHOLD { score += 20 }
        }
        if score > bestScore { bestScore = score; bestAction = action }
    }

    let preview = applyCandidate(state, bestAction)
    return (bestAction, preview.evolution)
}

private func rolloutGreedy(_ state: GameState, _ maxTurns: Int = 16) {
    var turn = 0
    while turn < maxTurns && !state.ended {
        if let pick = chooseGreedyTurn(state) {
            applyMainAction(state, pick.action)
            if let e = pick.evolution { applyEvolution(state, e) }
        }
        finishTurn(state)
        turn += 1
    }
}

/// 실제 AI 턴용 강화 정책: 상위 후보를 가상 적용한 뒤 짧은 greedy rollout 으로 비교한다.
public func chooseStrongTurn(_ state: GameState, _ rng: Rng? = nil) -> (action: MainAction, evolution: Evolution?)? {
    let playerIndex = state.currentPlayer
    let player = state.players[playerIndex]
    let actions = legalMainActions(state)
    if actions.isEmpty { return nil }

    let goal = goalSet(state, player)
    let candidates = actions.map { action -> (action: MainAction, pre: Double) in
        var pre = actionValue(state, player, action, goal) + blockValue(state, playerIndex, action) * 0.65
        if case let .acquire(cardId, _) = action { pre += Double(cardOf(cardId).points) * 1.1 }
        return (action, pre)
    }
    .sorted { $0.pre > $1.pre }
    .prefix(min(18, actions.count))

    let candArr = Array(candidates)
    var bestAction = candArr[0].action
    var bestScore = -Double.infinity
    for candidate in candArr {
        let preview = applyCandidate(state, candidate.action)
        let beforeFinishEval = stateEval(preview.state, playerIndex)
        finishTurn(preview.state)
        rolloutGreedy(preview.state, 14)

        var score = candidate.pre + beforeFinishEval * 0.24 + stateEval(preview.state, playerIndex) * 0.58
        if preview.state.ended && winnerId(preview.state) == playerIndex { score += 10_000 }
        if let rng = rng { score += rng.next() * 0.001 }

        if score > bestScore { bestScore = score; bestAction = candidate.action }
    }

    let preview = applyCandidate(state, bestAction)
    return (bestAction, preview.evolution)
}
