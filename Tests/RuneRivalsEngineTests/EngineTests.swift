// 엔진 규칙 단위 테스트. `swift test` 로 실행.

import XCTest
@testable import RuneRivalsEngine

final class EngineTests: XCTestCase {

    func testDeckComposition() {
        XCTAssertEqual(deckOf(.stage(1)).count, 35)
        XCTAssertEqual(deckOf(.stage(2)).count, 30)
        XCTAssertEqual(deckOf(.stage(3)).count, 15)
        XCTAssertEqual(deckOf(.rare).count, 5)
        XCTAssertEqual(deckOf(.legendary).count, 5)
        XCTAssertEqual(CARDS.count, 90)
    }

    func testRuneRivalsCharacters() {
        // 캐릭터 교체 확인: 룬 라이벌즈 이름이 실제로 덱에 있는지.
        let names = Set(CARDS.map { $0.romanized })
        XCTAssertTrue(names.contains("kai"))
        XCTAssertTrue(names.contains("tide_kai"))
        XCTAssertTrue(names.contains("red_nova"))
        XCTAssertTrue(names.contains("master_rook"))
        // 원본(드래곤볼) 이름이 남아있지 않은지.
        XCTAssertFalse(names.contains("goku"))
        XCTAssertFalse(names.contains("shenron"))
    }

    func testEvolutionLinks() {
        // 모든 진화 대상이 실제 존재.
        for c in CARDS {
            guard let evo = c.evolvesTo else { continue }
            XCTAssertFalse(cardsByRomanized(evo).isEmpty, "\(c.romanized) → \(evo) 대상 없음")
        }
    }

    func testInitialBoard() {
        let s = createGame(seed: 1, numPlayers: 4)
        XCTAssertEqual(s.board[.stage(1)]?.count, 4)
        XCTAssertEqual(s.board[.stage(2)]?.count, 4)
        XCTAssertEqual(s.board[.stage(3)]?.count, 4)
        XCTAssertEqual(s.board[.rare]?.count, 1)
        XCTAssertEqual(s.board[.legendary]?.count, 1)
    }

    func testDeterminism() {
        func run() -> (Int, [Int]) {
            let s = createGame(seed: 777, numPlayers: 4)
            let rng = Rng(seed: 42)
            var turns = 0
            while !s.ended && turns < 4000 {
                if let pick = chooseStrongTurn(s, rng) { takeTurn(s, pick.action, pick.evolution) }
                else { finishTurn(s) }
                turns += 1
            }
            return (turns, s.players.map { playerPoints($0) })
        }
        let a = run()
        let b = run()
        XCTAssertEqual(a.0, b.0)
        XCTAssertEqual(a.1, b.1)
    }

    func testGameTerminatesAndWinnerValid() {
        let s = createGame(seed: 3, numPlayers: 4)
        let rng = Rng(seed: 3)
        var turns = 0
        while !s.ended && turns < 4000 {
            if let pick = chooseStrongTurn(s, rng) { takeTurn(s, pick.action, pick.evolution) }
            else { finishTurn(s) }
            turns += 1
        }
        XCTAssertTrue(s.ended, "게임 미종료")
        XCTAssertGreaterThanOrEqual(playerPoints(s.players[winnerId(s)]), WIN_THRESHOLD)
    }

    func testBallConservation() {
        let s = createGame(seed: 5, numPlayers: 4)
        let rng = Rng(seed: 5)
        func total(_ bc: BallColor) -> Int {
            (s.supply[bc] ?? 0) + s.players.reduce(0) { $0 + ($1.balls[bc] ?? 0) }
        }
        let cut = 0 // 4인
        var turns = 0
        while !s.ended && turns < 500 {
            if let pick = chooseStrongTurn(s, rng) { takeTurn(s, pick.action, pick.evolution) }
            else { finishTurn(s) }
            for c in [BallColor.red, .blue, .black, .pink, .yellow] {
                XCTAssertEqual(total(c), (INITIAL_BALL_SUPPLY[c] ?? 0) - cut)
            }
            XCTAssertEqual(total(.gold), INITIAL_BALL_SUPPLY[.gold] ?? 0)
            turns += 1
        }
    }

    func testEvolutionAvailableImmediatelyAfterAcquiredBonusCompletesCondition() throws {
        let source = try XCTUnwrap(CARDS.first {
            stageOf($0.tier) == 1 &&
            ($0.evoCost?[.blue] ?? 0) == 2 &&
            ($0.bonus[.blue] ?? 0) == 0
        })
        let target = try XCTUnwrap(cardsByRomanized(try XCTUnwrap(source.evolvesTo)).first)
        let bonusCard = try XCTUnwrap(CARDS.first {
            stageOf($0.tier) == 1 &&
            ($0.bonus[.blue] ?? 0) == 1 &&
            $0.id != source.id
        })
        let s = focusedState()
        let p = s.players[0]
        score(source, for: p)
        p.bonus[.blue] = 1
        s.board[bonusCard.tier] = [bonusCard.id]
        s.board[target.tier] = [target.id]

        XCTAssertTrue(legalEvolutions(s).isEmpty)
        let pay = try XCTUnwrap(computePay(p, bonusCard))
        XCTAssertTrue(canApplyMainAction(s, .acquire(cardId: bonusCard.id, pay: pay)))

        applyMainAction(s, .acquire(cardId: bonusCard.id, pay: pay))

        XCTAssertEqual(p.bonus[.blue], 2)
        XCTAssertTrue(legalEvolutions(s).contains { $0.sourceId == source.id && $0.targetId == target.id })
    }

    func testEvolutionAvailableWhenMainActionRefillsBoardWithTarget() throws {
        let source = try XCTUnwrap(CARDS.first { stageOf($0.tier) == 1 && $0.evolvesTo != nil })
        let target = try XCTUnwrap(cardsByRomanized(try XCTUnwrap(source.evolvesTo)).first)
        let placeholder = try XCTUnwrap(CARDS.first {
            $0.tier == target.tier &&
            $0.romanized != target.romanized
        })
        let s = focusedState()
        let p = s.players[0]
        score(source, for: p)
        for (color, count) in try XCTUnwrap(source.evoCost) {
            p.bonus[color] = max(p.bonus[color] ?? 0, count)
        }
        s.board[target.tier] = [placeholder.id]
        s.decks[target.tier] = [target.id]

        XCTAssertFalse(boardCardIds(s).contains(target.id))
        XCTAssertTrue(legalEvolutions(s).isEmpty)
        let pay = try XCTUnwrap(computePay(p, placeholder))

        applyMainAction(s, .acquire(cardId: placeholder.id, pay: pay))

        XCTAssertTrue(boardCardIds(s).contains(target.id))
        XCTAssertTrue(legalEvolutions(s).contains { $0.sourceId == source.id && $0.targetId == target.id })
    }

    private func focusedState() -> GameState {
        let s = createGame(seed: 99, numPlayers: 3, humanIndex: 0)
        s.currentPlayer = 0
        s.startingPlayer = 0
        s.turnOrder = [0, 1, 2]
        s.triggeredEnd = false
        s.ended = false
        s.evolvedThisTurn = false
        for tier in TIERS {
            s.board[tier] = []
            s.decks[tier] = []
        }
        let p = s.players[0]
        p.balls = BALL_COLORS.reduce(into: [:]) { balls, color in balls[color] = 10 }
        p.bonus = emptyColorMap()
        p.reserved = []
        p.blindReserved = []
        p.scored = []
        p.evolutions = 0
        return s
    }

    private func score(_ card: CardDef, for player: PlayerState) {
        player.scored.append(card.id)
        for (color, count) in card.bonus {
            player.bonus[color, default: 0] += count
        }
    }
}
