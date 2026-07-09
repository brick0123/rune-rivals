// 보드: 3·2·1단계 공개 카드 행(+비공개 보관 버튼) + 전설·희귀 행. 각 행 가로 스크롤.

import SwiftUI

struct BoardView: View {
    @Bindable var vm: GameViewModel
    let onTapCard: (CardDef) -> Void

    private let cardW: CGFloat = 84

    var body: some View {
        // 세로 스택. 각 행은 폭이 넘치면 가로 스크롤(카드 겹침 방지).
        VStack(spacing: 10) {
            nobleRow()
            ForEach([3, 2, 1], id: \.self) { tier in
                stageRow(tier)
            }
        }
    }

    private func stageRow(_ tier: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                deckPile(.stage(tier))
                ForEach(vm.boardSlots(.stage(tier)), id: \.self) { id in
                    let card = cardOf(id)
                    CardView(card: card, width: cardW,
                             dimmed: !(vm.canAcquire(id) || vm.canReserveCard(id)) && vm.isHumanTurn && vm.phase == .main)
                        .onTapGesture { onTapCard(card) }
                }
                ForEach(0..<max(0, REVEAL_PER_STAGE - vm.boardSlots(.stage(tier)).count), id: \.self) { _ in
                    emptySlot
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // 전설·희귀: 각각 좌측에 덱 탭(보관 불가 → 비활성, 남은 장수만 표시) + 공개 카드. 가로 스크롤.
    private func nobleRow() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                deckPile(.legendary)
                nobleCard(.legendary)
                deckPile(.rare)
                nobleCard(.rare)
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func nobleCard(_ tier: Tier) -> some View {
        if let id = vm.boardSlots(tier).first {
            let card = cardOf(id)
            CardView(card: card, width: cardW,
                     dimmed: !vm.canAcquire(id) && vm.isHumanTurn && vm.phase == .main)
                .onTapGesture { onTapCard(card) }
        } else {
            emptySlot
        }
    }

    private func deckPile(_ tier: Tier) -> some View {
        let stage = stageOf(tier)
        // 단계 덱은 "Lv1/Lv2/Lv3", 전설·희귀 덱은 등급명 그대로.
        let tabLabel = stage > 0 ? "Lv\(stage)" : tier.label
        return Button {
            if vm.canReserveBlind(stage) { vm.reserveBlind(stage) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(Theme.surfaceHi)
                    .frame(width: cardW * 0.5, height: cardW / Theme.cardAspect)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(tier.accent.opacity(0.5), lineWidth: 1))
                VStack(spacing: 2) {
                    Text(tabLabel).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    Text("\(vm.deckCount(tier))").font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(.white)
                    if vm.canReserveBlind(stage) {
                        Image(systemName: "hand.raised.fill").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                    }
                }
            }
        }
        .disabled(!vm.canReserveBlind(stage))
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: Theme.cardCorner)
            .fill(Theme.surface.opacity(0.4))
            .frame(width: cardW, height: cardW / Theme.cardAspect)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}
