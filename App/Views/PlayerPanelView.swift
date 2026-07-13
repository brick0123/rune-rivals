// 플레이어 패널. compact=상대 요약, full=현재 사람 상세(손패·보너스·보관).

import SwiftUI

struct PlayerPanelView: View {
    @Bindable var vm: GameViewModel
    let playerIdx: Int
    /// 현재 턴 좌석. 부모가 값으로 주입 → 턴 변경 시 입력이 바뀌어 패널이 확실히 재렌더된다.
    let currentSeat: Int
    var full: Bool = false
    var onTapReserved: ((CardDef) -> Void)? = nil

    private var p: PlayerState { vm.state.players[playerIdx] }
    private var isCurrent: Bool { currentSeat == playerIdx && !vm.state.ended }

    var body: some View {
        VStack(alignment: .leading, spacing: full ? 8 : 4) {
            header
            if full {
                fullBody
            } else {
                compactBody
            }
        }
        .padding(full ? 12 : 11)
        .background(isCurrent ? Theme.surfaceHi : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? SwiftUI.Color.green : .clear, lineWidth: 2)
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isCurrent { Circle().fill(SwiftUI.Color.green).frame(width: 7, height: 7) }
            Text(vm.playerNames[playerIdx])
                .font(full ? .headline : .subheadline.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            // 가장 먼저 시작한 플레이어 표시(별 왼쪽).
            if playerIdx == vm.state.startingPlayer {
                Text("F")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 16, height: 16)
                    .background(.orange, in: Circle())
            }
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

    // 상대 요약: 구슬(전 색)·보너스(획득 카드 색)를 항상(0이면 흐리게) 표시 → 내 패널처럼 한눈에 보유 파악.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 구슬 — 5색 + gold, 0은 흐리게, 우측에 총 개수
            HStack(spacing: 5) {
                ForEach(BALL_COLORS, id: \.self) { bc in
                    let n = p.balls[bc] ?? 0
                    Ball(color: bc, count: n, size: 28).opacity(n > 0 ? 1 : 0.25)
                }
                Spacer(minLength: 2)
                Text("\(handBallCount(p))/\(MAX_BALLS_IN_HAND)")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textDim)
            }
            // 카드 보너스 — 5색, 0은 흐리게
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                ForEach(COLORS, id: \.self) { c in
                    let n = p.bonus[c] ?? 0
                    pill(text: "\(n)", color: Theme.color(c), size: 24).opacity(n > 0 ? 1 : 0.3)
                }
                Spacer(minLength: 0)
            }
            // 획득/찜 카드 — 모두 공개(찜 = 주황 테두리)
            cardsStrip(60)
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 손패 구슬 + 총 개수(N/최대)
            HStack(spacing: 6) {
                ForEach(BALL_COLORS, id: \.self) { bc in
                    let n = p.balls[bc] ?? 0
                    Ball(color: bc, count: n, size: 30)
                        .opacity(n > 0 ? 1 : 0.28)
                }
                Spacer(minLength: 4)
                VStack(spacing: 0) {
                    Text("\(handBallCount(p))/\(MAX_BALLS_IN_HAND)")
                        .font(.subheadline.weight(.black)).foregroundStyle(.white)
                    Text("공").font(.system(size: 9)).foregroundStyle(Theme.textDim)
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
            // 카드(획득 + 찜) — 모두 공개. 찜 = 주황 테두리, 탭하면 상세/획득.
            cardsStrip(52)
        }
    }

    /// 획득(scored) + 찜(reserved) 카드를 가로로 나열 — 모든 플레이어에게 공개.
    /// 찜 카드는 주황 테두리 + 손 아이콘으로 구분. onTapReserved 가 있으면(내 패널) 찜 카드 탭 시 상세/획득.
    @ViewBuilder
    private func cardsStrip(_ size: CGFloat) -> some View {
        if !p.scored.isEmpty || !p.reserved.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(p.scored, id: \.self) { id in
                        CardView(card: cardOf(id), width: size)
                    }
                    ForEach(p.reserved, id: \.self) { id in
                        let card = cardOf(id)
                        CardView(card: card, width: size,
                                 dimmed: onTapReserved != nil && !vm.canAcquire(id) && vm.phase == .main)
                            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(.orange, lineWidth: 2))
                            .overlay(alignment: .topLeading) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: max(8, size * 0.2), weight: .bold))
                                    .foregroundStyle(.orange).padding(2)
                            }
                            .onTapGesture { onTapReserved?(card) }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func pill(text: String, color: SwiftUI.Color, size: CGFloat = 20) -> some View {
        Text(text)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: size)
            .padding(.vertical, size * 0.1)
            .background(color, in: Capsule())
    }
}
