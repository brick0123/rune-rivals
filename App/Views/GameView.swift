// 게임 메인 화면. 상대 요약 + 보드 + 현재 플레이어 패널 + 구슬 + 액션 바 + 카드 상세/종료.

import SwiftUI

struct GameView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CardDef?
    @State private var detailReserved = false

    /// 하단 상세 패널의 대상 플레이어 = 사람(P0).
    private var focusIdx: Int { 0 }
    /// 상대 인덱스 — 턴 순서 기준(내 다음 차례부터 위→아래 순). 내 패널은 항상 맨 아래.
    /// 예) 턴 나→A2→A1 이면 [A2, A1] / 턴 A2→나→A1 이면 [A1, A2].
    private var opponentIndices: [Int] {
        let order = vm.state.turnOrder
        guard let myPos = order.firstIndex(of: focusIdx), order.count > 1 else {
            return order.filter { $0 != focusIdx }
        }
        return (1..<order.count).map { order[(myPos + $0) % order.count] }
    }

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
                // 카드 상세 — 전체 화면 시트 대신 중앙 플로팅 팝업(뒤 보드가 비쳐 보임, 바깥 탭 시 닫힘).
                if let card = detail {
                    CardDetailPopup(vm: vm, card: card, reserved: detailReserved) { detail = nil }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.easeInOut(duration: 0.15), value: detail)
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

    // 가로: 좌(뒤로가기 + 보드) | 우(상대 패널들 + 내 조작 레일, 세로 스크롤).
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 8) {
                HStack { backButton; Spacer() }
                boardScroll
            }
            .frame(maxWidth: .infinity)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(opponentIndices, id: \.self) { i in
                        PlayerPanelView(vm: vm, playerIdx: i, currentSeat: vm.currentSeat)
                    }
                    bottom
                }
            }
            .frame(width: 330)
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
                ForEach(opponentIndices, id: \.self) { i in
                    PlayerPanelView(vm: vm, playerIdx: i, currentSeat: vm.currentSeat)
                        .frame(width: 190)
                }
            }
            .padding(.horizontal, 10)
        }
        // 가로 스크롤이 세로 공간을 잠식하지 않도록 콘텐츠 높이에 고정 → 보드 세로 스크롤 영역 확보.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var bottom: some View {
        VStack(spacing: 8) {
            PlayerPanelView(vm: vm, playerIdx: focusIdx, currentSeat: vm.currentSeat, full: true) { card in
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

/// 카드 상세 팝업 — 전체 화면을 가리지 않는 중앙 플로팅 카드 + 획득/찜/진화 버튼.
struct CardDetailPopup: View {
    @Bindable var vm: GameViewModel
    let card: CardDef
    let reserved: Bool
    let close: () -> Void
    @State private var showReserveConfirm = false

    var body: some View {
        ZStack {
            // 살짝만 어둡게(뒤 보드가 비쳐 보임). 바깥 탭 시 닫힘.
            SwiftUI.Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 10) {
                CardView(card: card, width: 150)
                Text(card.name).font(.headline).foregroundStyle(.white)
                Text(card.tier.label).font(.caption).foregroundStyle(card.tier.accent)

                // 비용
                HStack(spacing: 5) {
                    ForEach(COLORS.filter { (card.cost[$0] ?? 0) > 0 }, id: \.self) { c in
                        CostPip(color: c, count: card.cost[c] ?? 0, size: 22)
                    }
                    if isNoble(card.tier) { CostPip(color: nil, count: 1, size: 22) }
                }

                // 액션 — 구매/찜/진화 항상 표시. 가능하면 컬러, 불가하면 회색+비활성.
                HStack(spacing: 8) {
                    let canBuy = vm.canAcquire(card.id)
                    Button { vm.acquire(card.id); close() } label: {
                        Text("구매").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canBuy ? .blue : .gray)
                    .disabled(!canBuy)

                    // 찜: 아직 안 찜한 보드 카드만(내 찜 카드는 제외), 최대 3개(MAX_RESERVED)까지.
                    let canReserve = !reserved && vm.canReserveCard(card.id)
                    Button {
                        if vm.reserveNeedsConfirm(card.id) { showReserveConfirm = true }
                        else { vm.reserve(card.id); close() }
                    } label: {
                        Text("찜").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(canReserve ? .orange : .gray)
                    .disabled(!canReserve)

                    let canEvo = vm.canEvolveInto(card.id)
                    Button { vm.evolveInto(card.id); close() } label: {
                        Text("진화").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(canEvo ? .cyan : .gray)
                    .disabled(!canEvo)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: 300)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .padding(24)
        }
        .confirmationDialog("찜코인 없이 가져올까요?", isPresented: $showReserveConfirm, titleVisibility: .visible) {
            Button("가져오기") { vm.reserve(card.id); close() }
            Button("취소", role: .cancel) { }
        } message: {
            Text(vm.supplyCount(.gold) == 0 ? "남은 찜코인이 없어요." : "구슬이 10개라 찜코인을 받을 수 없어요.")
        }
    }
}
