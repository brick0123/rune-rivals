// 정적 구슬 데이터. 색 = 컬러 5종 + gold(궁극의 룬 오브, 와일드).

import Foundation

public let BALLS: [BallDef] = [
    BallDef(id: .red,    name: "붉은 오브",       romanized: "red_orb",    color: .red,    isMaster: false),
    BallDef(id: .blue,   name: "푸른 오브",       romanized: "blue_orb",   color: .blue,   isMaster: false),
    BallDef(id: .black,  name: "검은 오브",       romanized: "black_orb",  color: .black,  isMaster: false),
    BallDef(id: .pink,   name: "분홍 오브",       romanized: "pink_orb",   color: .pink,   isMaster: false),
    BallDef(id: .yellow, name: "노란 오브",       romanized: "yellow_orb", color: .yellow, isMaster: false),
    BallDef(id: .gold,   name: "궁극의 룬 오브",  romanized: "rune_orb",   color: .gold,   isMaster: true),
]

public let BALLS_BY_ID: [BallColor: BallDef] = Dictionary(
    uniqueKeysWithValues: BALLS.map { ($0.id, $0) }
)

/// UI 표시용 컬러명. gold 는 name 그대로 사용.
public let COLOR_DISPLAY: [BallColor: String] = [
    .red: "빨강", .blue: "초록", .black: "검정",
    .pink: "분홍", .yellow: "노랑", .gold: "궁극의 룬 오브",
]

/// 게임 시작 시 공급 가능한 구슬 수.
public let INITIAL_BALL_SUPPLY: [BallColor: Int] = [
    .red: 7, .blue: 7, .black: 7, .pink: 7, .yellow: 7, .gold: 5,
]

/// 컬러 구슬 보유 한도.
public let MAX_BALLS_IN_HAND = 10
/// 보관(예약) 카드 한도.
public let MAX_RESERVED = 3
/// 각 단계 덱에서 공개되는 카드 수. 희귀·전설은 1장씩.
public let REVEAL_PER_STAGE = 4
