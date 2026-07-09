// 정적 카드 데이터 — 룬 라이벌즈 캐릭터.
// 규칙 수치(비용·점수·진화비용·덱 크기)는 원본 스플렌더 변형 룰을 100% 유지하고,
// 캐릭터 이름/romanized(에셋 키)만 룬 라이벌즈로 교체한다.
// 라인 색상은 blue,yellow,red,pink,black × 3 순환 — 라인별로 3단계 진화(1→2→3).

import Foundation

/// 한 단계의 표시명(한글) + 에셋 키(romanized).
public struct StageName: Sendable {
    public let ko: String
    public let rom: String
    public init(_ ko: String, _ rom: String) { self.ko = ko; self.rom = rom }
}

/// 진화 라인: 세 단계 이름 + 라인 보너스색(3단계 모두 동일).
struct LineSpec {
    let color: Color
    let s1: StageName
    let s2: StageName
    let s3: StageName
}

// 라인 1~15. 색상은 원본 룰의 라인 색과 정확히 대응(캐릭터만 룬 라이벌즈).
let LINES: [LineSpec] = [
    LineSpec(color: .blue,   s1: StageName("카이", "kai"),      s2: StageName("아쿠아 카이", "aqua_kai"),   s3: StageName("타이드 카이", "tide_kai")),
    LineSpec(color: .yellow, s1: StageName("레오", "leo"),      s2: StageName("솔라 레오", "solar_leo"),     s3: StageName("선 레오", "sun_leo")),
    LineSpec(color: .red,    s1: StageName("린", "rin"),        s2: StageName("루비 린", "ruby_rin"),        s3: StageName("플레임 린", "flame_rin")),
    LineSpec(color: .pink,   s1: StageName("미라", "mira"),     s2: StageName("루나 미라", "luna_mira"),      s3: StageName("드림 미라", "dream_mira")),
    LineSpec(color: .black,  s1: StageName("녹스", "nox"),      s2: StageName("보이드 녹스", "void_nox"),     s3: StageName("나이트 녹스", "night_nox")),
    LineSpec(color: .blue,   s1: StageName("아이비", "ivy"),    s2: StageName("쏜 아이비", "thorn_ivy"),      s3: StageName("블룸 아이비", "bloom_ivy")),
    LineSpec(color: .yellow, s1: StageName("볼트", "bolt"),     s2: StageName("플래시 볼트", "flash_bolt"),   s3: StageName("스카이 볼트", "sky_bolt")),
    LineSpec(color: .red,    s1: StageName("브랜", "bran"),     s2: StageName("스파크 브랜", "spark_bran"),   s3: StageName("포지 브랜", "forge_bran")),
    LineSpec(color: .pink,   s1: StageName("나이라", "nyra"),   s2: StageName("마스크 나이라", "mask_nyra"),  s3: StageName("트릭 나이라", "trick_nyra")),
    LineSpec(color: .black,  s1: StageName("기어", "gear"),     s2: StageName("클락 기어", "clock_gear"),     s3: StageName("블랙 기어", "black_gear")),
    LineSpec(color: .blue,   s1: StageName("루미", "lumi"),     s2: StageName("송 루미", "song_lumi"),        s3: StageName("웨이브 루미", "wave_lumi")),
    LineSpec(color: .yellow, s1: StageName("아리", "ari"),      s2: StageName("라이트 아리", "light_ari"),    s3: StageName("윙 아리", "wing_ari")),
    LineSpec(color: .red,    s1: StageName("마일로", "milo"),   s2: StageName("스파크 마일로", "spark_milo"), s3: StageName("블래스트 마일로", "blast_milo")),
    LineSpec(color: .pink,   s1: StageName("베라", "vera"),     s2: StageName("문 베라", "moon_vera"),        s3: StageName("크리스탈 베라", "crystal_vera")),
    LineSpec(color: .black,  s1: StageName("룬", "rune"),       s2: StageName("다크 룬", "dark_rune"),        s3: StageName("나이트 룬", "night_rune")),
]

/// 1·2단계 카드 스펙: (점수, 비용, 진화비용).
typealias EvoCardSpec = (points: Int, cost: ColorMap, evoCost: ColorMap)
/// 3단계 카드 스펙: (점수, 비용). 진화 없음.
typealias LeafCardSpec = (points: Int, cost: ColorMap)

// 라인 순서는 LINES 와 동일. 각 라인의 1단계 카드들(변형 포함).
let STAGE1: [[EvoCardSpec]] = [
    [(1, [.black: 3, .pink: 2], [.yellow: 3]), (1, [.blue: 4], [.yellow: 3])],
    [(1, [.red: 3, .black: 2], [.pink: 3]),    (1, [.yellow: 4], [.pink: 3])],
    [(1, [.pink: 3, .blue: 2], [.black: 3]),   (1, [.red: 4], [.black: 3])],
    [(1, [.blue: 3, .yellow: 2], [.red: 3]),   (1, [.pink: 4], [.red: 3])],
    [(1, [.yellow: 3, .red: 2], [.blue: 3]),   (1, [.black: 4], [.blue: 3])],
    [(0, [.black: 1, .yellow: 1, .pink: 1, .red: 1], [.pink: 3]), (0, [.red: 2, .yellow: 1, .blue: 1], [.pink: 3])],
    [(0, [.blue: 1, .red: 1, .pink: 1, .black: 1], [.black: 3]),  (0, [.pink: 2, .black: 1, .red: 1], [.black: 3])],
    [(0, [.blue: 1, .yellow: 1, .pink: 1, .black: 1], [.yellow: 3]), (0, [.yellow: 2, .pink: 1, .black: 1], [.yellow: 3])],
    [(0, [.blue: 1, .yellow: 1, .red: 1, .black: 1], [.blue: 3]), (0, [.black: 2, .blue: 1, .yellow: 1], [.blue: 3])],
    [(0, [.red: 1, .yellow: 1, .pink: 1, .blue: 1], [.red: 3]),   (0, [.blue: 2, .red: 1, .pink: 1], [.red: 3])],
    [(0, [.yellow: 2, .black: 1], [.red: 2]), (0, [.blue: 2, .red: 2], [.red: 2]),   (0, [.pink: 3], [.red: 2])],
    [(0, [.red: 2, .pink: 1], [.blue: 2]),    (0, [.blue: 2, .yellow: 2], [.blue: 2]), (0, [.black: 3], [.blue: 2])],
    [(0, [.black: 2, .blue: 1], [.pink: 2]),  (0, [.pink: 2, .red: 2], [.pink: 2]),  (0, [.yellow: 3], [.pink: 2])],
    [(0, [.blue: 2, .yellow: 1], [.black: 2]), (0, [.pink: 2, .black: 2], [.black: 2]), (0, [.red: 3], [.black: 2])],
    [(0, [.pink: 2, .red: 1], [.yellow: 2]),  (0, [.yellow: 2, .black: 2], [.yellow: 2]), (0, [.blue: 3], [.yellow: 2])],
]

let STAGE2: [[EvoCardSpec]] = [
    [(3, [.yellow: 4, .black: 4, .red: 1], [.red: 4]),  (3, [.blue: 6], [.red: 4])],
    [(3, [.red: 4, .pink: 4, .blue: 1], [.blue: 4]),    (3, [.yellow: 6], [.blue: 4])],
    [(3, [.blue: 4, .black: 4, .pink: 1], [.pink: 4]),  (3, [.red: 6], [.pink: 4])],
    [(3, [.red: 4, .yellow: 4, .black: 1], [.black: 4]), (3, [.pink: 6], [.black: 4])],
    [(3, [.blue: 4, .pink: 4, .yellow: 1], [.yellow: 4]), (3, [.black: 6], [.yellow: 4])],
    [(2, [.pink: 4, .yellow: 2, .black: 1], [.black: 3]), (2, [.blue: 5, .red: 2], [.black: 3])],
    [(2, [.black: 4, .pink: 2, .red: 1], [.red: 3]),    (2, [.yellow: 5, .blue: 2], [.red: 3])],
    [(2, [.yellow: 4, .black: 2, .blue: 1], [.blue: 3]), (2, [.red: 5, .pink: 2], [.blue: 3])],
    [(2, [.blue: 4, .red: 2, .yellow: 1], [.yellow: 3]), (2, [.pink: 5, .black: 2], [.yellow: 3])],
    [(2, [.red: 4, .blue: 2, .pink: 1], [.pink: 3]),    (2, [.black: 5, .yellow: 2], [.pink: 3])],
    [(1, [.blue: 3, .pink: 2, .black: 2], [.red: 4]),   (1, [.red: 3, .yellow: 2, .pink: 2], [.red: 4])],
    [(1, [.yellow: 3, .pink: 2, .red: 2], [.blue: 4]),  (1, [.blue: 3, .pink: 2, .black: 2], [.blue: 4])],
    [(1, [.red: 3, .black: 2, .yellow: 2], [.pink: 4]), (1, [.pink: 3, .yellow: 2, .black: 2], [.pink: 4])],
    [(1, [.pink: 3, .blue: 2, .yellow: 2], [.black: 4]), (1, [.black: 3, .blue: 2, .red: 2], [.black: 4])],
    [(1, [.black: 3, .blue: 2, .red: 2], [.yellow: 4]), (1, [.yellow: 3, .blue: 2, .red: 2], [.yellow: 4])],
]

let STAGE3: [[LeafCardSpec]] = [
    [(5, [.black: 7, .yellow: 3])],
    [(5, [.red: 7, .pink: 3])],
    [(5, [.blue: 7, .black: 3])],
    [(5, [.yellow: 7, .red: 3])],
    [(5, [.pink: 7, .blue: 3])],
    [(4, [.pink: 6, .red: 4])],
    [(4, [.black: 6, .blue: 4])],
    [(4, [.yellow: 6, .pink: 4])],
    [(4, [.blue: 6, .black: 4])],
    [(4, [.red: 6, .yellow: 4])],
    [(3, [.blue: 5, .black: 2, .yellow: 2])],
    [(3, [.yellow: 5, .red: 2, .pink: 2])],
    [(3, [.red: 5, .black: 2, .blue: 2])],
    [(3, [.pink: 5, .yellow: 2, .red: 2])],
    [(3, [.black: 5, .blue: 2, .pink: 2])],
]

/// 희귀 카드: (한글명, romanized, 보너스색, 비용). 점수 0, 보너스 2. 색상은 원본 룰과 대응.
let RARE: [(ko: String, rom: String, color: Color, cost: ColorMap)] = [
    ("마스터 루크", "master_rook",  .red,    [.black: 3, .blue: 2]),
    ("세이지 블루", "sage_blue",    .blue,   [.pink: 3, .yellow: 2]),
    ("골드 벨",     "gold_bell",    .yellow, [.blue: 3, .pink: 2]),
    ("레이디 루나", "lady_luna",    .pink,   [.red: 3, .black: 2]),
    ("블랙 퀼",     "black_quill",  .black,  [.yellow: 3, .red: 2]),
]

/// 전설 카드: (한글명, romanized, 보너스색, 비용). 점수 2, 보너스 2. 유니크 존재.
let LEGENDARY: [(ko: String, rom: String, color: Color, cost: ColorMap)] = [
    ("레드 노바",     "red_nova",    .red,    [.pink: 3, .blue: 3, .yellow: 3]),
    ("블루 아틀라스", "blue_atlas",  .blue,   [.black: 3, .yellow: 3, .red: 3]),
    ("골드 아스트라", "gold_astra",  .yellow, [.red: 3, .pink: 3, .black: 3]),
    ("문 세라프",     "moon_seraph", .pink,   [.blue: 3, .yellow: 3, .black: 3]),
    ("보이드 이지스", "void_aegis",  .black,  [.pink: 3, .red: 3, .blue: 3]),
]

// MARK: - 덱 빌드

private func bonusOf(_ color: Color, _ n: Int) -> ColorMap { [color: n] }

private func build() -> [CardDef] {
    var out: [CardDef] = []
    var counters: [String: Int] = [:]
    func nextId(_ prefix: String) -> String {
        counters[prefix, default: 0] += 1
        return "\(prefix)-" + String(format: "%03d", counters[prefix]!)
    }

    for (i, line) in LINES.enumerated() {
        // 1단계
        for spec in STAGE1[i] {
            out.append(CardDef(
                id: nextId("s1"), name: line.s1.ko, romanized: line.s1.rom, tier: .stage(1),
                points: spec.points, bonus: bonusOf(line.color, 1), cost: spec.cost,
                evolvesTo: line.s2.rom, evoCost: spec.evoCost
            ))
        }
        // 2단계
        for spec in STAGE2[i] {
            out.append(CardDef(
                id: nextId("s2"), name: line.s2.ko, romanized: line.s2.rom, tier: .stage(2),
                points: spec.points, bonus: bonusOf(line.color, 1), cost: spec.cost,
                evolvesTo: line.s3.rom, evoCost: spec.evoCost
            ))
        }
        // 3단계
        for spec in STAGE3[i] {
            out.append(CardDef(
                id: nextId("s3"), name: line.s3.ko, romanized: line.s3.rom, tier: .stage(3),
                points: spec.points, bonus: bonusOf(line.color, 1), cost: spec.cost
            ))
        }
    }

    for r in RARE {
        out.append(CardDef(
            id: nextId("rare"), name: r.ko, romanized: r.rom, tier: .rare,
            points: 0, bonus: bonusOf(r.color, 2), cost: r.cost
        ))
    }
    for l in LEGENDARY {
        out.append(CardDef(
            id: nextId("leg"), name: l.ko, romanized: l.rom, tier: .legendary,
            points: 2, bonus: bonusOf(l.color, 2), cost: l.cost
        ))
    }
    return out
}

public let CARDS: [CardDef] = build()

public let CARDS_BY_ID: [String: CardDef] = Dictionary(
    uniqueKeysWithValues: CARDS.map { ($0.id, $0) }
)

/// romanized 가 일치하는 모든 카드(진화 대상 검색용).
public func cardsByRomanized(_ romanized: String) -> [CardDef] {
    CARDS.filter { $0.romanized == romanized }
}

/// 단계별 덱 구성(셔플 대상). 각 단계는 동일 이름 변형을 포함한 모든 카드.
public func deckOf(_ tier: Tier) -> [CardDef] {
    CARDS.filter { $0.tier == tier }
}

public let DECK_SIZES: [Tier: Int] = [
    .stage(1): 35, .stage(2): 30, .stage(3): 15, .rare: 5, .legendary: 5,
]
