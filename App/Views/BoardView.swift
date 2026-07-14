// 보드: 3·2·1단계 공개 카드 행(+비공개 보관 버튼) + 전설·희귀 행. 각 행 가로 스크롤.

import SwiftUI

struct BoardView: View {
    @Bindable var vm: GameViewModel
    let onTapCard: (CardDef) -> Void
    @State private var pendingBlindStage: Int?

    private let cardW: CGFloat = 96

    var body: some View {
        // 세로 스택(왼쪽 정렬). 각 행은 폭이 넘치면 가로 스크롤(카드 겹침 방지).
        VStack(alignment: .leading, spacing: 10) {
            nobleRow()
            ForEach([3, 2, 1], id: \.self) { tier in
                stageRow(tier)
            }
        }
        .alert("블라인드 찜할까요?",
               isPresented: Binding(get: { pendingBlindStage != nil },
                                    set: { if !$0 { pendingBlindStage = nil } }),
               presenting: pendingBlindStage) { stage in
            Button("예") { vm.reserveBlind(stage); pendingBlindStage = nil }
            Button("아니요", role: .cancel) { pendingBlindStage = nil }
        } message: { _ in
            Text("덱 맨 위 카드를 안 보고 가져갑니다. 상대는 뒷면(레벨)만 볼 수 있어요.")
        }
    }

    private func stageRow(_ tier: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                deckPile(.stage(tier))
                ForEach(vm.boardSlots(.stage(tier)), id: \.self) { id in
                    let card = cardOf(id)
                    CardView(card: card, width: cardW,
                             dimmed: !(vm.canAcquire(id) || vm.canReserveCard(id) || vm.canEvolveInto(id)) && vm.isHumanTurn && vm.phase == .main,
                             evolveReady: vm.canEvolveInto(id))
                        .onTapGesture { onTapCard(card) }
                }
                ForEach(0..<max(0, REVEAL_PER_STAGE - vm.boardSlots(.stage(tier)).count), id: \.self) { _ in
                    emptySlot
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private func deckPile(_ tier: Tier) -> some View {
        let stage = stageOf(tier)
        // 단계 덱은 "Lv1/Lv2/Lv3", 전설·희귀 덱은 등급명 그대로.
        let tabLabel = stage > 0 ? "Lv\(stage)" : tier.label
        if stage > 0 {
            // 단계 덱만 블라인드 찜 가능(버튼).
            let canBlind = vm.canReserveBlind(stage)
            Button {
                if canBlind { pendingBlindStage = stage }
            } label: {
                deckTab(tier, tabLabel, showHand: canBlind)
            }
            .disabled(!canBlind)
        } else {
            // 희귀·전설: 찜/블라인드 찜 불가 → 표시 전용(버튼 아님).
            deckTab(tier, tabLabel, showHand: false)
        }
    }

    private func deckTab(_ tier: Tier, _ label: String, showHand: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Theme.surfaceHi)
                .frame(width: cardW * 0.38, height: cardW / Theme.cardAspect)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(tier.accent.opacity(0.5), lineWidth: 1))
            VStack(spacing: 2) {
                Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                Text("\(vm.deckCount(tier))").font(.system(size: 15, weight: .black, design: .rounded)).foregroundStyle(.white)
                if showHand {
                    Image(systemName: "hand.raised.fill").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: Theme.cardCorner)
            .fill(Theme.surface.opacity(0.4))
            .frame(width: cardW, height: cardW / Theme.cardAspect)
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }
}
