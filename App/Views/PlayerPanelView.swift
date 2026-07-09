// 플레이어 패널. compact=상대 요약, full=현재 사람 상세(손패·보너스·보관).

import SwiftUI
import RuneRivalsEngine

struct PlayerPanelView: View {
    @Bindable var vm: GameViewModel
    let playerIdx: Int
    var full: Bool = false
    var onTapReserved: ((CardDef) -> Void)? = nil

    private var p: PlayerState { vm.state.players[playerIdx] }
    private var isCurrent: Bool { vm.state.currentPlayer == playerIdx && !vm.state.ended }

    var body: some View {
        VStack(alignment: .leading, spacing: full ? 8 : 4) {
            header
            if full {
                fullBody
            } else {
                compactBody
            }
        }
        .padding(full ? 12 : 8)
        .background(isCurrent ? Theme.surfaceHi : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isCurrent { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
            Text(vm.playerNames[playerIdx])
                .font(full ? .headline : .caption.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Label("\(vm.points(playerIdx))", systemImage: "star.fill")
                .font(full ? .subheadline.weight(.bold) : .caption2.weight(.bold))
                .foregroundStyle(.yellow)
            if p.evolutions > 0 {
                Label("\(p.evolutions)", systemImage: "arrow.up.circle.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
            }
        }
    }

    // 상대 요약: 보너스(획득 카드 수) + 볼 총수 + 보관 수
    private var compactBody: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(COLORS, id: \.self) { c in
                    let n = p.bonus[c] ?? 0
                    if n > 0 {
                        pill(text: "\(n)", color: Theme.color(c))
                    }
                }
            }
            Spacer()
            Image(systemName: "circle.grid.2x2.fill").font(.system(size: 9)).foregroundStyle(Theme.textDim)
            Text("\(handBallCount(p))").font(.caption2).foregroundStyle(Theme.textDim)
            if !p.reserved.isEmpty {
                Image(systemName: "hand.raised.fill").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                Text("\(p.reserved.count)").font(.caption2).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 손패 구슬
            HStack(spacing: 6) {
                ForEach(BALL_COLORS, id: \.self) { bc in
                    let n = p.balls[bc] ?? 0
                    Ball(color: bc, count: n, size: 30)
                        .opacity(n > 0 ? 1 : 0.28)
                }
            }
            // 보너스(획득 카드 컬러)
            HStack(spacing: 6) {
                Text("보너스").font(.caption2).foregroundStyle(Theme.textDim)
                ForEach(COLORS, id: \.self) { c in
                    let n = p.bonus[c] ?? 0
                    pill(text: "\(n)", color: Theme.color(c)).opacity(n > 0 ? 1 : 0.3)
                }
            }
            // 보관 카드
            if !p.reserved.isEmpty {
                HStack(spacing: 6) {
                    Text("보관").font(.caption2).foregroundStyle(Theme.textDim)
                    ForEach(p.reserved, id: \.self) { id in
                        let card = cardOf(id)
                        CardView(card: card, width: 52,
                                 dimmed: !vm.canAcquire(id) && vm.phase == .main)
                            .onTapGesture { onTapReserved?(card) }
                    }
                }
            }
        }
    }

    private func pill(text: String, color: SwiftUI.Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 20)
            .padding(.vertical, 2)
            .background(color, in: Capsule())
    }
}
