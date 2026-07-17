// 공용 룬 공급대. 컬러 5색은 탭으로 선택(1개→2개→해제 순환), gold 는 비선택(획득 시 자동).

import SwiftUI

struct BallSupplyView: View {
    @Bindable var vm: GameViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(COLORS, id: \.self) { c in
                colorChip(c)
            }
            goldChip
        }
    }

    private func colorChip(_ c: Color) -> some View {
        let bc = BallColor(rawValue: c.rawValue)!
        let picked = vm.pickedCount(c)
        let n = vm.supplyCount(bc)
        return Ball(color: bc, count: n, size: 44, selected: picked > 0, badge: picked, style: .coinRim)
            .onTapGesture {
                if n > 0 { SoundPlayer.play("pop") }
                vm.tapColor(c)
            }
            .opacity(n > 0 ? 1 : 0.35)
    }

    private var goldChip: some View {
        Ball(color: .gold, count: vm.supplyCount(.gold), size: 44, selected: false, style: .coinRim)
            .opacity(vm.supplyCount(.gold) > 0 ? 1 : 0.35)
    }
}

enum BallStyle {
    case colored
    case coinRim
}

/// 룬 하나(색 원 + 개수).
struct Ball: View {
    let color: BallColor
    var count: Int? = nil
    var size: CGFloat = 40
    var selected: Bool = false
    /// 선택한 개수(0=미선택, 1·2). 1 이상이면 우상단 배지 표시.
    var badge: Int = 0
    var style: BallStyle = .colored

    @State private var glow = false
    private var isGold: Bool { color == .gold }

    var body: some View {
        tokenBody
            .frame(width: size, height: size)
            .overlay(tokenStroke)
            .overlay {
                if let count {
                    Text("\(count)")
                        .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                        .foregroundStyle(textColor)
                }
            }
            // 선택 개수 배지(우상단): 1개/2개 구분 표시.
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 1.5))
                        .offset(x: size * 0.12, y: -size * 0.12)
                }
            }
            // 마스터 룬(골드)은 반짝이는 보라 글로우로 강조.
            .shadow(color: shadowColor,
                    radius: isGold ? (glow ? 10 : 4) : (selected ? 5 : 0))
            .scaleEffect(selected ? 1.08 : 1)
            .animation(.spring(duration: 0.2), value: selected)
            .onAppear {
                if isGold {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true }
                }
            }
    }

    @ViewBuilder
    private var tokenBody: some View {
        switch style {
        case .colored:
            Circle()
                .fill(
                    RadialGradient(colors: [Theme.ballColor(color).opacity(0.95), Theme.ballColor(color)],
                                   center: .topLeading, startRadius: 1, endRadius: size)
                )
        case .coinRim:
            ZStack {
                Circle()
                    .fill(rimColor)
                Circle()
                    .fill(
                        RadialGradient(colors: [Theme.ballColor(color).opacity(0.95), Theme.ballColor(color)],
                                       center: .topLeading, startRadius: 1, endRadius: size)
                    )
                    .padding(size * 0.06)
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .offset(x: -size * 0.18, y: -size * 0.18)
                Circle()
                    .stroke(grooveColor, lineWidth: max(1.2, size * 0.07))
                    .padding(size * 0.16)
                RuneCoinMark()
                    .stroke(markColor, style: StrokeStyle(lineWidth: max(1.2, size * 0.09), lineJoin: .round))
                    .padding(size * 0.25)
            }
        }
    }

    @ViewBuilder
    private var tokenStroke: some View {
        switch style {
        case .colored:
            Circle().stroke(selected ? .white : .white.opacity(0.5), lineWidth: selected ? 3 : 1)
        case .coinRim:
            Circle().stroke(selected ? .white : .white.opacity(0.5), lineWidth: selected ? 3 : 1)
        }
    }

    private var textColor: SwiftUI.Color {
        switch style {
        case .colored:
            return Theme.onBall(color)
        case .coinRim:
            return Theme.onBall(color)
        }
    }

    private var shadowColor: SwiftUI.Color {
        switch style {
        case .colored, .coinRim:
            return isGold ? Theme.ballColor(.gold).opacity(0.9) : (selected ? .white.opacity(0.5) : .clear)
        }
    }

    private var rimColor: SwiftUI.Color {
        switch color {
        case .red:
            return SwiftUI.Color(red: 0.62, green: 0.15, blue: 0.17)
        case .blue:
            return SwiftUI.Color(red: 0.08, green: 0.60, blue: 0.26)
        case .black:
            return SwiftUI.Color(red: 0.18, green: 0.20, blue: 0.27)
        case .pink:
            return SwiftUI.Color(red: 0.73, green: 0.17, blue: 0.50)
        case .yellow:
            return SwiftUI.Color(red: 0.76, green: 0.54, blue: 0.00)
        case .gold:
            return SwiftUI.Color(red: 0.42, green: 0.15, blue: 0.70)
        }
    }

    private var grooveColor: SwiftUI.Color {
        color == .yellow ? .black.opacity(0.26) : rimColor.opacity(0.58)
    }

    private var markColor: SwiftUI.Color {
        color == .yellow ? .black.opacity(0.15) : .white.opacity(0.19)
    }
}

private struct RuneCoinMark: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.5))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h))
        path.addLine(to: CGPoint(x: x, y: y + h * 0.5))
        path.closeSubpath()

        path.move(to: CGPoint(x: x + w * 0.24, y: y + h * 0.5))
        path.addLine(to: CGPoint(x: x + w * 0.76, y: y + h * 0.5))
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.22))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h * 0.78))
        return path
    }
}
