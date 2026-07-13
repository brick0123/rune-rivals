// 공용 구슬 공급대. 컬러 5색은 탭으로 선택(1개→2개→해제 순환), gold 는 비선택(획득 시 자동).

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
        return Ball(color: bc, count: n, size: 44, selected: picked > 0, badge: picked)
            .onTapGesture {
                if n > 0 { SoundPlayer.play("pop") }
                vm.tapColor(c)
            }
            .opacity(n > 0 ? 1 : 0.35)
    }

    private var goldChip: some View {
        Ball(color: .gold, count: vm.supplyCount(.gold), size: 44, selected: false)
            .opacity(vm.supplyCount(.gold) > 0 ? 1 : 0.35)
    }
}

/// 구슬 하나(색 원 + 개수).
struct Ball: View {
    let color: BallColor
    var count: Int? = nil
    var size: CGFloat = 40
    var selected: Bool = false
    /// 선택한 개수(0=미선택, 1·2). 1 이상이면 우상단 배지 표시.
    var badge: Int = 0

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
