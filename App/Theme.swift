// UI 테마: 엔진 Color/BallColor → SwiftUI Color 매핑 + 표시 헬퍼 + 레이아웃 상수.

import SwiftUI

enum Theme {
    // 배경/표면
    static let bg = SwiftUI.Color(red: 0.06, green: 0.09, blue: 0.16)
    static let surface = SwiftUI.Color(red: 0.11, green: 0.15, blue: 0.24)
    static let surfaceHi = SwiftUI.Color(red: 0.16, green: 0.21, blue: 0.32)
    static let stroke = SwiftUI.Color.white.opacity(0.12)
    static let textDim = SwiftUI.Color.white.opacity(0.55)

    /// 컬러 볼 → 표시색.
    static func color(_ c: Color) -> SwiftUI.Color {
        switch c {
        case .red:    return SwiftUI.Color(red: 0.90, green: 0.26, blue: 0.28)
        case .blue:   return SwiftUI.Color(red: 0.204, green: 0.780, blue: 0.369) // 표시상 초록(내부 식별자는 blue 유지)
        case .black:  return SwiftUI.Color(red: 0.30, green: 0.33, blue: 0.42)
        case .pink:   return SwiftUI.Color(red: 0.93, green: 0.42, blue: 0.72)
        case .yellow: return SwiftUI.Color(red: 0.98, green: 0.78, blue: 0.20)
        }
    }

    static func ballColor(_ c: BallColor) -> SwiftUI.Color {
        if let cc = c.asColor { return color(cc) }
        // 마스터 룬(궁극의 룬 오브) — 노랑과 구분되도록 반짝이는 보라.
        return SwiftUI.Color(red: 0.635, green: 0.294, blue: 0.941)
    }

    /// 볼 위 글자색(노란색만 어둡게, 나머지는 흰색).
    static func onBall(_ c: BallColor) -> SwiftUI.Color {
        c == .yellow ? .black.opacity(0.8) : .white
    }

    /// 컬러 한 글자 라벨.
    static func short(_ c: BallColor) -> String {
        switch c {
        case .red: return "R"; case .blue: return "G"; case .black: return "K"
        case .pink: return "P"; case .yellow: return "Y"; case .gold: return "★"
        }
    }

    static let cardCorner: CGFloat = 12
    static let cardAspect: CGFloat = 591.0 / 887.0  // 원본 카드 비율(w/h)
}

extension Tier {
    /// UI 표시명.
    var label: String {
        switch self {
        case .stage(1): return "1단계"
        case .stage(2): return "2단계"
        case .stage(3): return "3단계"
        case .stage:    return "?"
        case .rare:     return "희귀"
        case .legendary: return "전설"
        }
    }
    /// 등급 강조색.
    var accent: SwiftUI.Color {
        switch self {
        case .stage(1): return .green
        case .stage(2): return .cyan
        case .stage(3): return .purple
        case .stage:    return .gray
        case .rare:     return .orange
        case .legendary: return .yellow
        }
    }
}
