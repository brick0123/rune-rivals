// 도메인 공유 타입. data·game·strategy·sim 모두 사용.
// UI 는 이 타입들을 렌더링에 참조 가능하나, 규칙 함수만이 상태를 변경한다.

import Foundation

/// 컬러 볼 5색. 보너스 색과 동일.
public enum Color: String, CaseIterable, Hashable, Sendable, Codable {
    case red, blue, black, pink, yellow
}

/// 전 컬러 목록(TS COLORS 순서 유지: red, blue, black, pink, yellow).
public let COLORS: [Color] = [.red, .blue, .black, .pink, .yellow]

/// 볼 색 = 5컬러 + gold(궁극의 룬 오브, 와일드카드).
public enum BallColor: String, CaseIterable, Hashable, Sendable, Codable {
    case red, blue, black, pink, yellow, gold

    /// 컬러(비-gold)면 대응 Color, gold 면 nil.
    public var asColor: Color? { Color(rawValue: rawValue) }
}

public let BALL_COLORS: [BallColor] = [.red, .blue, .black, .pink, .yellow, .gold]

/// 카드 등급. 희귀(rare)와 전설(legendary)은 별개 덱이지만 규칙상 동일 취급(gold 필수·보관불가).
public enum Tier: Hashable, Sendable {
    case stage(Int)   // 1, 2, 3
    case rare
    case legendary

    public static let s1 = Tier.stage(1)
    public static let s2 = Tier.stage(2)
    public static let s3 = Tier.stage(3)

    /// 정렬·딕셔너리 키 안정성을 위한 순서 인덱스.
    public var order: Int {
        switch self {
        case .stage(let n): return n
        case .rare: return 4
        case .legendary: return 5
        }
    }
}

/// 전 tier 목록(TS TIERS 순서: 1,2,3,rare,legendary).
public let TIERS: [Tier] = [.stage(1), .stage(2), .stage(3), .rare, .legendary]
/// 단계 덱만(진화 대상).
public let STAGE_TIERS: [Int] = [1, 2, 3]

/// 컬러→수량 맵. 0 인 항목은 생략(부분 레코드).
public typealias ColorMap = [Color: Int]

/// 카드 정의(정적). 덱·보드·보관 더미는 id 로 카드를 참조한다.
public struct CardDef: Hashable, Sendable {
    /// 고유 덱 id, 예: "s1-001" · "rare-01" · "leg-03"
    public let id: String
    /// 한글 표시 이름(동일 이름의 변형 카드가 여러 장일 수 있음).
    public let name: String
    /// 에셋 파일명 키(romanized). 동일 진화 라인은 단계별로 서로 다른 romanized.
    public let romanized: String
    public let tier: Tier
    public let points: Int
    /// 획득 시 제공하는 컬러 보너스(비용 할인). 1·2·3단계=1, 희귀·전설=2.
    public let bonus: ColorMap
    /// 획득 비용(컬러 볼). 보너스 할인 적용 전 원가.
    public let cost: ColorMap
    /// 1·2단계만: 진화 대상 romanized.
    public let evolvesTo: String?
    /// 1·2단계만: 진화에 필요한 컬러 보너스(획득 카드 보너스 합계로 충족).
    public let evoCost: ColorMap?

    public init(id: String, name: String, romanized: String, tier: Tier,
                points: Int, bonus: ColorMap, cost: ColorMap,
                evolvesTo: String? = nil, evoCost: ColorMap? = nil) {
        self.id = id
        self.name = name
        self.romanized = romanized
        self.tier = tier
        self.points = points
        self.bonus = bonus
        self.cost = cost
        self.evolvesTo = evolvesTo
        self.evoCost = evoCost
    }
}

/// 볼 정의(정적).
public struct BallDef: Hashable, Sendable {
    public let id: BallColor
    public let name: String
    public let romanized: String
    public let color: BallColor
    public let isMaster: Bool
}

/// 카드가 희귀/전설 등급(gold 필수·보관불가)인지.
public func isNoble(_ tier: Tier) -> Bool {
    tier == .rare || tier == .legendary
}

/// 카드의 단계(희귀/전설은 0 — 진화 대상 아님).
public func stageOf(_ tier: Tier) -> Int {
    switch tier {
    case .stage(let n): return n
    case .rare, .legendary: return 0
    }
}
