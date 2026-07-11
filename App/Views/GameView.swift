// 게임 메인 화면. 상대 요약 + 보드 + 현재 플레이어 패널 + 구슬 + 액션 바 + 카드 상세/종료.

import SwiftUI

struct GameView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CardDef?
    @State private var detailReserved = false

    /// 하단 상세 패널의 대상 플레이어 = 사람(P0).
    private var focusIdx: Int { 0 }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Theme.bg.ignoresSafeArea()
                if landscape { landscapeLayout } else { portraitLayout }

                if vm.phase == .gameOver {
                    GameOverView(vm: vm)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $detail) { card in
            CardDetailSheet(vm: vm, card: card, reserved: detailReserved) { detail = nil }
                .presentationDetents([.height(360)])
        }
        .animation(.easeInOut, value: vm.phase)
    }

    // 세로: 위에서 아래로 상대 → 보드 → 내 조작.
    private var portraitLayout: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) { backButton; opponents }
            boardScroll
            bottom
        }
        .padding(.top, 6)
    }

    // 가로: 좌(상대 + 보드) | 우(내 조작 레일).
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                HStack(spacing: 8) { backButton; opponents }
                boardScroll
            }
            .frame(maxWidth: .infinity)
            ScrollView {
                bottom
            }
            .frame(width: 300)
        }
        .padding(8)
    }

    private var boardScroll: some View {
        ScrollView {
            BoardView(vm: vm) { card in openDetail(card, reserved: false) }
                .padding(.horizontal, 8)
        }
    }

    // 네비바 제거 후 메뉴 복귀용 컴팩트 버튼(상대 목록 줄에 인라인 배치 → 세로 공간 미소비).
    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.surface, in: Circle())
        }
    }

    private var opponents: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<vm.state.numPlayers, id: \.self) { i in
                    if i != focusIdx {
                        PlayerPanelView(vm: vm, playerIdx: i)
                            .frame(width: 190)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        // 가로 스크롤이 세로 공간을 잠식하지 않도록 콘텐츠 높이에 고정 → 보드 세로 스크롤 영역 확보.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bottom: some View {
        VStack(spacing: 8) {
            PlayerPanelView(vm: vm, playerIdx: focusIdx, full: true) { card in
                openDetail(card, reserved: true)
            }
            if vm.isHumanTurn && vm.phase == .main {
                BallSupplyView(vm: vm)
            }
            ActionBarView(vm: vm)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func openDetail(_ card: CardDef, reserved: Bool) {
        guard vm.isHumanTurn, vm.phase == .main else { return }
        detailReserved = reserved
        detail = card
    }
}

/// 카드 상세 + 획득/보관 버튼.
struct CardDetailSheet: View {
    @Bindable var vm: GameViewModel
    let card: CardDef
    let reserved: Bool
    let close: () -> Void
    @State private var showReserveConfirm = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            HStack(spacing: 18) {
                CardView(card: card, width: 130)
                VStack(alignment: .leading, spacing: 12) {
                    Text(card.name).font(.title2.weight(.bold)).foregroundStyle(.white)
                    Text(card.tier.label).font(.subheadline).foregroundStyle(card.tier.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("비용").font(.caption).foregroundStyle(Theme.textDim)
                        HStack(spacing: 5) {
                            ForEach(COLORS.filter { (card.cost[$0] ?? 0) > 0 }, id: \.self) { c in
                                CostPip(color: c, count: card.cost[c] ?? 0, size: 24)
                            }
                            if isNoble(card.tier) { CostPip(color: nil, count: 1, size: 24) }
                        }
                    }

                    Spacer()
                    VStack(spacing: 8) {
                        Button {
                            vm.acquire(card.id); close()
                        } label: {
                            Text("획득").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canAcquire(card.id))

                        if !reserved {
                            Button {
                                if vm.reserveNeedsConfirm(card.id) { showReserveConfirm = true }
                                else { vm.reserve(card.id); close() }
                            } label: {
                                Text("찜").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).tint(.orange)
                            .disabled(!vm.canReserveCard(card.id))
                        }

                        // 진화 가능한 카드(1·2단계)만 노출. 3단계·전설·희귀는 진화 없음 → 숨김.
                        if card.evolvesTo != nil {
                            Button {
                                vm.evolveInto(card.id); close()
                            } label: {
                                Text("진화").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).tint(.cyan)
                            .disabled(!vm.canEvolveInto(card.id))
                        }
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog("찜코인 없이 가져올까요?", isPresented: $showReserveConfirm, titleVisibility: .visible) {
            Button("가져오기") { vm.reserve(card.id); close() }
            Button("취소", role: .cancel) { }
        } message: {
            Text(vm.supplyCount(.gold) == 0 ? "남은 찜코인이 없어요." : "구슬이 10개라 찜코인을 받을 수 없어요.")
        }
    }
}
