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

    // 상대 요약: 룬(전 색)·보너스(획득 카드 색)를 항상(0이면 흐리게) 표시 → 내 패널처럼 한눈에 보유 파악.
    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 룬 — 5색 + gold, 0은 흐리게, 우측에 총 개수
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
            // 손패 룬 + 총 개수(N/최대)
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
                    Text("룬").font(.system(size: 9)).foregroundStyle(Theme.textDim)
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

    private func pill(text: String, color: SwiftUI.Color, size: CGFloat = 20) -> some View {
        Text(text)
            .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: size)
            .padding(.vertical, size * 0.1)
            .background(color, in: Capsule())
    }
}
