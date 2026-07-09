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
}
