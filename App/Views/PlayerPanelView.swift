// 플레이어 패널. compact=상대 요약, full=현재 사람 상세(손패·보너스·보관).

import SwiftUI

struct PlayerPanelView: View {
    @Bindable var vm: GameViewModel
    let playerIdx: Int
    /// 현재 턴 좌석. 부모가 값으로 주입 → 턴 변경 시 입력이 바뀌어 패널이 확실히 재렌더된다.
    let currentSeat: Int
    var full: Bool = false
    /// 카드 탭 콜백 — (카드, 찜 여부). 획득 카드는 reserved=false, 찜 카드는 true.
    var onTapCard: ((CardDef, _ reserved: Bool) -> Void)? = nil
    /// 상대의 블라인드 찜(뒷면) 카드 탭 시 — "상대가 볼 수 없음" 안내용.
    var onTapHidden: (() -> Void)? = nil
    @State private var inventoryInfo: InventoryInfoKind?

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
        .alert(item: $inventoryInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("확인"))
            )
        }
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

    /// 색별 총 구매력 = 보유 룬(코인) + 카드 보너스.
    private func combinedCount(_ bc: BallColor) -> Int {
        (p.balls[bc] ?? 0) + (bc.asColor.flatMap { p.bonus[$0] } ?? 0)
    }

    private func infoButton<Content: View>(
        _ kind: InventoryInfoKind,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button { inventoryInfo = kind } label: {
            content()
                .frame(width: width, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind.title))
    }

    private var combinedIcon: some View {
        HStack(spacing: 3) {
            cardIcon(width: 10, height: 13)
            Image(systemName: "plus")
                .font(.system(size: 5, weight: .black))
                .foregroundStyle(Theme.textDim)
            runeIcon(size: 12)
        }
    }

    private func runeIcon(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.textDim, lineWidth: max(1.2, size * 0.12))
            RuneInventoryMark()
                .fill(Theme.textDim)
                .padding(size * 0.25)
        }
        .frame(width: size, height: size)
    }

    private func cardIcon(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.2)
                .stroke(Theme.textDim, lineWidth: max(1.2, width * 0.12))
            VStack(alignment: .leading, spacing: height * 0.18) {
                Capsule().fill(Theme.textDim).frame(width: width * 0.5, height: max(1.2, height * 0.08))
                Capsule().fill(Theme.textDim).frame(width: width * 0.34, height: max(1.2, height * 0.08))
            }
        }
        .frame(width: width, height: height)
    }

    private var cardCountBadge: some View {
        HStack(spacing: 3) {
            cardIcon(width: 10, height: 13)
            Text("\(p.scored.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.textDim)
        .accessibilityLabel(Text("카드 \(p.scored.count)장"))
    }

    /// 위: 룬+카드 합계(색별 총 구매력) / 아래: 코인(룬) 현황 + 손 룬 총개수.
    private func runeRows(_ ballSize: CGFloat) -> some View {
        let heldBallSize = max(22, ballSize * 0.88)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                infoButton(.combined, width: 32) { combinedIcon }
                ForEach(BALL_COLORS, id: \.self) { bc in
                    let n = combinedCount(bc)
                    Ball(color: bc, count: n, size: ballSize).opacity(n > 0 ? 1 : 0.25)
                }
                Spacer(minLength: 2)
            }
            HStack(spacing: 5) {
                infoButton(.runes, width: 32) { runeIcon(size: 14) }
                ForEach(BALL_COLORS, id: \.self) { bc in
                    let n = p.balls[bc] ?? 0
                    Ball(color: bc, count: n, size: heldBallSize, style: .coinRim).opacity(n > 0 ? 1 : 0.25)
                }
                Spacer(minLength: 2)
                HStack(spacing: 6) {
                    cardCountBadge
                    Text("\(handBallCount(p))/\(MAX_BALLS_IN_HAND)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Theme.textDim)
            }
        }
    }

    // 상대 요약: 룬+카드 합계 / 코인 현황 / 획득·찜 카드.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            runeRows(28)
            cardsStrip(60)
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            runeRows(30)
            // 카드(획득 + 찜) — 모두 공개. 찜 = 주황 테두리, 탭하면 상세/획득.
            cardsStrip(52)
        }
    }

    /// 획득 카드를 카드 색(COLORS 순: 빨→초→검→분홍→노랑)으로 그룹핑. 같은 색은 획득 순서 유지.
    private func scoredByColor() -> [[String]] {
        var groups: [Color: [String]] = [:]
        for id in p.scored {
            let c = cardOf(id).bonus.keys.first ?? .red
            groups[c, default: []].append(id)
        }
        return COLORS.compactMap { groups[$0] }.filter { !$0.isEmpty }
    }

    /// 같은 색 획득 카드 한 컬럼 — 세로로 부분 포갬(위 카드가 아래로 겹쳐 최신이 앞·아래, 이전 카드 상단만 보임).
    private func scoredColumn(_ group: [String], _ size: CGFloat) -> some View {
        let cardH = size / Theme.cardAspect
        let off = cardH * 0.24
        return ZStack(alignment: .top) {
            ForEach(Array(group.enumerated()), id: \.element) { idx, id in
                CardView(card: cardOf(id), width: size)
                    .onTapGesture { onTapCard?(cardOf(id), false) }
                    .offset(y: CGFloat(idx) * off)
                    .zIndex(Double(idx))
            }
        }
        .frame(width: size, height: cardH + CGFloat(max(0, group.count - 1)) * off, alignment: .top)
    }

    /// 획득(scored, 별도 줄·색 정렬·포갬) + 찜(reserved, 별도 줄) 카드 — 모든 플레이어에게 공개.
    @ViewBuilder
    private func cardsStrip(_ size: CGFloat) -> some View {
        // 획득 카드 줄 — 카드 색(COLORS) 순 정렬, 같은 색은 세로로 부분 포갬.
        if !p.scored.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(scoredByColor().enumerated()), id: \.offset) { _, group in
                        scoredColumn(group, size)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        // 찜 카드 줄 — 별도 행(주황 표시). 상대의 블라인드 찜은 뒷면(레벨)만.
        if !p.reserved.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(p.reserved, id: \.self) { id in
                        let card = cardOf(id)
                        if !p.isHuman && vm.isBlindReserved(p.id, id) {
                            faceDownReserved(card.tier, size)
                                .onTapGesture { onTapHidden?() }
                        } else {
                            CardView(card: card, width: size,
                                     dimmed: p.isHuman && !vm.canAcquire(id) && vm.phase == .main)
                                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(.orange, lineWidth: 2))
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: max(8, size * 0.2), weight: .bold))
                                        .foregroundStyle(.orange).padding(2)
                                }
                                .onTapGesture { onTapCard?(card, true) }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// 상대 블라인드 찜 카드의 뒷면 — 레벨(tier)만 노출, 앞면 비공개.
    private func faceDownReserved(_ tier: Tier, _ size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Theme.cardCorner)
            .fill(Theme.surfaceHi)
            .frame(width: size, height: size / Theme.cardAspect)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(tier.accent.opacity(0.7), lineWidth: 2))
            .overlay {
                VStack(spacing: 2) {
                    Image(systemName: "eye.slash.fill").font(.system(size: size * 0.22)).foregroundStyle(Theme.textDim)
                    Text(tier.label).font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: max(8, size * 0.2), weight: .bold))
                    .foregroundStyle(.orange).padding(2)
            }
    }
}

private enum InventoryInfoKind: Identifiable {
    case combined
    case runes

    var id: String {
        switch self {
        case .combined: return "combined"
        case .runes: return "runes"
        }
    }

    var title: String {
        switch self {
        case .combined: return "카드 + 룬 합계"
        case .runes: return "보유 룬"
        }
    }

    var message: String {
        switch self {
        case .combined:
            return "색별 구매력입니다. 획득한 카드 보너스와 손에 든 룬을 합쳐 보여줍니다."
        case .runes:
            return "현재 손에 들고 있는 룬 개수입니다. 오른쪽의 카드 아이콘 숫자는 획득한 카드 수입니다."
        }
    }
}

private struct RuneInventoryMark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.0))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.5),
            control1: CGPoint(x: x + w * 0.56, y: y + h * 0.28),
            control2: CGPoint(x: x + w * 0.72, y: y + h * 0.44)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h),
            control1: CGPoint(x: x + w * 0.72, y: y + h * 0.56),
            control2: CGPoint(x: x + w * 0.56, y: y + h * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: x, y: y + h * 0.5),
            control1: CGPoint(x: x + w * 0.44, y: y + h * 0.72),
            control2: CGPoint(x: x + w * 0.28, y: y + h * 0.56)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.0),
            control1: CGPoint(x: x + w * 0.28, y: y + h * 0.44),
            control2: CGPoint(x: x + w * 0.44, y: y + h * 0.28)
        )
        path.closeSubpath()
        return path
    }
}
