// 공용 구슬 공급대. 컬러 5색은 선택 가능(take3), 4개↑면 2개 집기 가능. gold 는 비선택(획득 시 자동).

import SwiftUI
import RuneRivalsEngine

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
        let selected = vm.selectedColors.contains(c)
        let n = vm.supplyCount(bc)
        return VStack(spacing: 3) {
            Ball(color: bc, count: n, size: 44, selected: selected)
                .onTapGesture { vm.toggleColor(c) }
            if vm.canTake2(c) {
                Button("×2") { vm.take2(c) }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceHi, in: Capsule())
            } else {
                Color.clear.frame(height: 18)
            }
        }
        .opacity(n > 0 ? 1 : 0.35)
    }

    private var goldChip: some View {
        VStack(spacing: 3) {
            Ball(color: .gold, count: vm.supplyCount(.gold), size: 44, selected: false)
            Color.clear.frame(height: 18)
        }
        .opacity(vm.supplyCount(.gold) > 0 ? 1 : 0.35)
    }
}

/// 구슬 하나(색 원 + 개수).
struct Ball: View {
    let color: BallColor
    var count: Int? = nil
    var size: CGFloat = 40
    var selected: Bool = false

    @State private var glow = false
    private var isGold: Bool { color == .gold }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [Theme.ballColor(color).opacity(0.95), Theme.ballColor(color)],
                               center: .topLeading, startRadius: 1, endRadius: size)
            )
            .frame(width: size, height: size)
            .overlay(Circle().stroke(selected ? .white : .white.opacity(0.5), lineWidth: selected ? 3 : 1))
            .overlay {
                if let count {
                    Text("\(count)")
                        .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.onBall(color))
                }
            }
            // 찜코인(골드)은 반짝이는 보라 글로우로 강조.
            .shadow(color: isGold ? Theme.ballColor(.gold).opacity(0.9) : (selected ? .white.opacity(0.5) : .clear),
                    radius: isGold ? (glow ? 10 : 4) : (selected ? 5 : 0))
            .scaleEffect(selected ? 1.08 : 1)
            .animation(.spring(duration: 0.2), value: selected)
            .onAppear {
                if isGold {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true }
                }
            }
    }
}
