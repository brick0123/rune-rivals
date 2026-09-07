// 온라인 일반전 — 매치메이킹(오버워치식). 진입 시 자동으로 매칭 큐 참가 → 성사되면 대전 시작.

import SwiftUI

struct OnlineLobbyView: View {
    let ranked: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var client = RelayClient()
    @State private var status: Status = .connecting
    @State private var elapsed = 0
    @State private var queueSize = 1
    @State private var gameVM: GameViewModel?
    @State private var inGame = false
    @State private var started = false
    @State private var didMatch = false
    @State private var ticker: Timer?

    enum Status { case connecting, searching, matched, failed }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 22) {
                Text(ranked ? "랭크전" : "일반전")
                    .font(.title.weight(.black)).foregroundStyle(.white)

                switch status {
                case .connecting, .searching:
                    ProgressView().controlSize(.large).tint(.white)
                    Text(status == .connecting ? "서버 연결 중…" : "매칭 찾는 중…")
                        .font(.headline).foregroundStyle(.white)
                    Text("\(elapsed)초 경과 · \(queueSize)명 대기 중")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                    Text("2명 모이면 곧 시작, 3명이면 3인전")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                    Button("취소") { cancel() }
                        .buttonStyle(.bordered).tint(.gray)
                case .matched:
                    ProgressView().tint(.white)
                    Text("매칭 완료! 입장 중…").font(.headline).foregroundStyle(.white)
                case .failed:
                    Image(systemName: "wifi.slash").font(.system(size: 40)).foregroundStyle(.red)
                    Text("서버 연결에 실패했어요").font(.headline).foregroundStyle(.white)
                    Button("다시 시도") { start() }.buttonStyle(.borderedProminent)
                    Button("메뉴로") { cancel() }.buttonStyle(.bordered).tint(.gray)
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $inGame) {
            if let vm = gameVM { GameView(vm: vm) }
        }
        .onAppear { if !started { started = true; start() } }
        .onChange(of: inGame) { _, now in
            if !now && didMatch { dismiss() }   // 게임 종료 후 복귀 → 메뉴로
        }
        .onDisappear { ticker?.invalidate() }
    }

    /// 닉네임(저장, 기본 랜덤).
    private var nickname: String {
        if let n = UserDefaults.standard.string(forKey: "nickname"), !n.isEmpty { return n }
        let n = "플레이어\(Int.random(in: 1000 ... 9999))"
        UserDefaults.standard.set(n, forKey: "nickname")
        return n
    }

    private func start() {
        status = .connecting
        elapsed = 0
        gameVM = nil
        let name = nickname
        client.onOpen = {
            status = .searching
            client.findMatch(name: name)
        }
        client.onEvent = { ev in handle(ev) }
        client.connect(RelayConfig.defaultURL)
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
            if status == .connecting && elapsed >= 20 { status = .failed; ticker?.invalidate() }
        }
    }

    private func handle(_ ev: RelayEvent) {
        switch ev {
        case .queued(let size):
            queueSize = max(size, 1)
        case let .joined(_, seat, isHost, roster, _, _):
            let names = roster.sorted { $0.seat < $1.seat }.map { $0.name }
            gameVM = GameViewModel(online: client, seat: seat, isHost: isHost, names: names)
            didMatch = true
            status = .matched
            ticker?.invalidate()
            inGame = true
        case .closed, .error:
            if status != .matched { status = .failed }
        default:
            break
        }
    }

    private func cancel() {
        client.cancelMatch()
        client.close()
        ticker?.invalidate()
        dismiss()
    }
}

#Preview { OnlineLobbyView(ranked: false) }
