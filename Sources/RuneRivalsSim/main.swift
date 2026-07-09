// 규칙 엔진 검증 하네스.
// 여러 시드로 AI-vs-AI 게임을 끝까지 진행하며 불변식을 assert 로 검증한다.
// 이 머신에는 iOS SDK 가 없어 UI 는 빌드 불가하지만, 순수 Swift 엔진은 `swift run RuneRivalsSim` 으로 검증된다.

import Foundation
import RuneRivalsEngine

// MARK: - 불변식 검사

/// 게임 전체 구슬 총량 = 초기 공급량(공급 + 모든 손패). 획득/반환이 보존적인지 확인.
func totalBalls(_ s: GameState) -> [BallColor: Int] {
    var total = s.supply
    for p in s.players {
        for bc in BALL_COLORS { total[bc, default: 0] += p.balls[bc] ?? 0 }
    }
    return total
}

func initialSupplyTotal(numPlayers: Int) -> [BallColor: Int] {
    let cut = numPlayers <= 2 ? 3 : (numPlayers == 3 ? 2 : 0)
    var t = INITIAL_BALL_SUPPLY
    for c in [BallColor.red, .blue, .black, .pink, .yellow] {
        t[c] = max(0, (INITIAL_BALL_SUPPLY[c] ?? 0) - cut)
    }
    return t
}

var failures = 0
func check(_ cond: Bool, _ msg: @autoclosure () -> String) {
    if !cond { failures += 1; print("  ❌ INVARIANT FAIL: \(msg())") }
}

func checkInvariants(_ s: GameState, expectedTotal: [BallColor: Int], seed: UInt32, turn: Int) {
    let total = totalBalls(s)
    for bc in BALL_COLORS {
        check(total[bc, default: 0] == expectedTotal[bc, default: 0],
              "seed \(seed) turn \(turn): ball \(bc.rawValue) 보존 위반 \(total[bc] ?? 0) != \(expectedTotal[bc] ?? 0)")
    }
    for p in s.players {
        check(handBallCount(p) <= MAX_BALLS_IN_HAND, "seed \(seed) p\(p.id): 손패 \(handBallCount(p)) > 10")
        check(p.reserved.count <= MAX_RESERVED, "seed \(seed) p\(p.id): 보관 \(p.reserved.count) > 3")
        for bc in BALL_COLORS {
            check((p.balls[bc] ?? 0) >= 0, "seed \(seed) p\(p.id): 음수 볼 \(bc.rawValue)")
        }
        for c in COLORS {
            check((p.bonus[c] ?? 0) >= 0, "seed \(seed) p\(p.id): 음수 보너스 \(c.rawValue)")
        }
    }
    for bc in BALL_COLORS {
        check((s.supply[bc] ?? 0) >= 0, "seed \(seed): 음수 공급 \(bc.rawValue)")
    }
}

// MARK: - 게임 1판 진행

struct GameResult {
    let winner: Int
    let turns: Int
    let points: [Int]
    let evolutions: [Int]
    let maxPoints: Int
}

func playGame(seed: UInt32, numPlayers: Int, maxTurns: Int = 4000) -> GameResult {
    let s = createGame(seed: seed, numPlayers: numPlayers, humanIndex: -1) // 전원 AI
    let expected = initialSupplyTotal(numPlayers: numPlayers)
    let choiceRng = Rng(seed: seed &+ 999)
    var turns = 0
    checkInvariants(s, expectedTotal: expected, seed: seed, turn: 0)

    while !s.ended && turns < maxTurns {
        if let pick = chooseStrongTurn(s, choiceRng) {
            takeTurn(s, pick.action, pick.evolution)
        } else {
            // 합법 행동 없음 → 강제 패스(finishTurn 만 수행).
            finishTurn(s)
        }
        turns += 1
        checkInvariants(s, expectedTotal: expected, seed: seed, turn: turns)
    }

    check(s.ended, "seed \(seed): \(maxTurns)턴 내 종료 실패(무한 루프 의심)")
    let winner = winnerId(s)
    check(playerPoints(s.players[winner]) >= WIN_THRESHOLD,
          "seed \(seed): 승자 점수 \(playerPoints(s.players[winner])) < \(WIN_THRESHOLD)")

    return GameResult(
        winner: winner,
        turns: turns,
        points: s.players.map { playerPoints($0) },
        evolutions: s.players.map { $0.evolutions },
        maxPoints: s.players.map { playerPoints($0) }.max() ?? 0
    )
}

// MARK: - 정적 데이터 검증

func checkDeckComposition() {
    print("== 덱 구성 검증 ==")
    let sizes: [(Tier, Int, String)] = [
        (.stage(1), 35, "1단계"), (.stage(2), 30, "2단계"), (.stage(3), 15, "3단계"),
        (.rare, 5, "희귀"), (.legendary, 5, "전설"),
    ]
    for (tier, expected, label) in sizes {
        let n = deckOf(tier).count
        check(n == expected, "\(label) 덱 크기 \(n) != \(expected)")
        print("  \(label): \(n)장 (기대 \(expected))")
    }
    check(CARDS.count == 90, "전체 카드 수 \(CARDS.count) != 90")
    print("  전체: \(CARDS.count)장")

    // 모든 stage1/2 카드의 evolvesTo 가 실제 다음 단계 카드 romanized 로 존재하는지.
    var evoOk = true
    for c in CARDS {
        guard let evo = c.evolvesTo else { continue }
        if cardsByRomanized(evo).isEmpty { evoOk = false; print("  ❌ 진화 대상 없음: \(c.romanized) → \(evo)") }
    }
    check(evoOk, "진화 대상 누락")
    print("  진화 링크: \(evoOk ? "OK" : "FAIL")")
}

func checkDeterminism() {
    print("== 결정론 검증 ==")
    let a = playGame(seed: 12345, numPlayers: 4)
    let b = playGame(seed: 12345, numPlayers: 4)
    check(a.winner == b.winner && a.turns == b.turns && a.points == b.points,
          "같은 시드가 다른 결과: \(a.winner)/\(a.turns) vs \(b.winner)/\(b.turns)")
    print("  seed 12345: 승자 P\(a.winner), \(a.turns)턴, 점수 \(a.points) — 재현 \(a.winner == b.winner && a.turns == b.turns ? "OK" : "FAIL")")
}

// MARK: - 실행

print("========================================")
print(" 룬 라이벌즈 엔진 검증")
print("========================================\n")

checkDeckComposition()
print("")
checkDeterminism()
print("")

for np in [2, 3, 4] {
    print("== \(np)인 게임 (시드 0~19) ==")
    var totalTurns = 0
    var winCounts = [Int: Int]()
    var maxPts = 0
    let games = 8
    for seed in 0..<UInt32(games) {
        let r = playGame(seed: seed, numPlayers: np)
        totalTurns += r.turns
        winCounts[r.winner, default: 0] += 1
        maxPts = max(maxPts, r.maxPoints)
    }
    let avg = Double(totalTurns) / Double(games)
    print(String(format: "  평균 %.1f턴, 최고점 %d, 승자분포 %@", avg, maxPts,
                 (0..<np).map { "P\($0):\(winCounts[$0] ?? 0)" }.joined(separator: " ")))
}

print("\n========================================")
if failures == 0 {
    print(" ✅ 모든 불변식 통과")
    print("========================================")
    exit(0)
} else {
    print(" ❌ \(failures)건 불변식 위반")
    print("========================================")
    exit(1)
}
