// 게임 메인 화면. 상대 요약 + 보드 + 현재 플레이어 패널 + 구슬 + 액션 바 + 카드 상세/종료.

import SwiftUI

struct GameView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CardDef?
    @State private var detailReserved = false
    @State private var showNewGameConfirm = false

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
        .confirmationDialog("새 게임을 시작할까요?", isPresented: $showNewGameConfirm, titleVisibility: .visible) {
            Button("새 게임", role: .destructive) { vm.newGame() }
            Button("취소", role: .cancel) { }
        } message: {
            Text("현재 게임이 초기화됩니다.")
        }
    }

    // 세로: 위에서 아래로 상대 → 보드 → 내 조작.
    private var portraitLayout: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) { backButton; timerView; newGameButton; opponents }
            boardScroll
            bottom
        }
        .padding(.top, 4)
    }

    // 가로: 좌(뒤로가기 + 보드) | 우(상대 패널들 + 내 조작 레일, 세로 스크롤).
    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 6) {
                HStack { backButton; Spacer(); timerView; Spacer(); newGameButton }
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
        .padding(.horizontal, 10).padding(.vertical, 4)
        // 왼쪽만 화면 끝까지 확장. 오른쪽은 세이프에어리어 유지(다이나믹 아일랜드가 우측 패널 가리는 것 방지).
        .ignoresSafeArea(.container, edges: .leading)
    }

    private var boardScroll: some View {
        ScrollView {
            BoardView(vm: vm) { card in openDetail(card, reserved: false) }
                .padding(.horizontal, 4)
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

    // 새 게임(같은 인원, 새 랜덤 시드/순서).
    private var newGameButton: some View {
        Button { showNewGameConfirm = true } label: {
            Label("새 게임", systemImage: "arrow.clockwise")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surfaceHi, in: Capsule())
        }
    }

    // 턴 타이머(남은 초). 10초 이하 빨강.
    private var timerView: some View {
        Label("\(vm.secondsLeft)", systemImage: "timer")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(vm.secondsLeft <= 10 ? SwiftUI.Color.red : .white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.surfaceHi, in: Capsule())
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

    // 진화 안내 — 카드 우측 여백. 진화 후 모습 + 진화에 필요한 보너스(evoCost).
    private var evolutionColumn: some View {
        VStack(spacing: 6) {
            Text("진화").font(.caption2.weight(.bold)).foregroundStyle(.cyan)
            Image(systemName: "arrow.up").font(.system(size: 18, weight: .black)).foregroundStyle(.cyan)
            Image(card.evolvesTo ?? "")
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .background(Theme.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SwiftUI.Color.cyan, lineWidth: 1.5))
            if let evo = card.evoCost, evo.values.contains(where: { $0 > 0 }) {
                Text("진화 조건").font(.system(size: 9)).foregroundStyle(Theme.textDim)
                VStack(spacing: 3) {
                    ForEach(COLORS.filter { (evo[$0] ?? 0) > 0 }, id: \.self) { c in
                        CostPip(color: c, count: evo[c] ?? 0, size: 20)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 92)
    }

    var body: some View {
        ZStack {
            // 살짝만 어둡게(뒤 보드가 비쳐 보임). 바깥 탭 시 닫힘.
            SwiftUI.Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    CardView(card: card, width: 150)
                    if card.evolvesTo != nil { evolutionColumn }
                }
                Text(card.name).font(.headline).foregroundStyle(.white)
                Text(card.tier.label).font(.caption).foregroundStyle(card.tier.accent)

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
            .frame(maxWidth: 340)
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
