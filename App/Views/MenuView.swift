// 시작 메뉴: 모드(싱글/일반/랭크) 선택. 싱글은 나+AI2(3인) 고정, 온라인은 방에서 인원 결정(최대 3인).

import SwiftUI

struct MenuView: View {
    @State private var mode: GameMode = .single
    @State private var startSingle = false
    @State private var openLobby = false
    @State private var seed: UInt32 = 1

    /// 싱글 기본 인원(나 + AI 2). 최대 3인.
    private let singlePlayers = 3

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    VStack(spacing: 6) {
                        Text("룬 라이벌즈")
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("RUNE RIVALS")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .tracking(6)
                            .foregroundStyle(Theme.textDim)
                    }

                    // 대표 캐릭터 미리보기
                    HStack(spacing: -18) {
                        ForEach(["kai", "flame_rin", "gold_astra", "night_rune"], id: \.self) { name in
                            Image(name)
                                .resizable().scaledToFill()
                                .frame(width: 66, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
                                .rotationEffect(.degrees(Double.random(in: -6...6)))
                        }
                    }
                    .padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 12) {
                        pickerBlock(title: "모드") {
                            Picker("", selection: $mode) {
                                ForEach(GameMode.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        Text(modeDesc)
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    Button {
                        guard mode.isAvailable else { return }
                        switch mode {
                        case .single: seed = UInt32.random(in: 1...UInt32.max); startSingle = true
                        case .casual: openLobby = true
                        case .ranked: break
                        }
                    } label: {
                        Text(startLabel)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(mode.isAvailable ? SwiftUI.Color("AccentColor") : Theme.surfaceHi,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(mode.isAvailable ? .white : Theme.textDim)
                    }
                    .disabled(!mode.isAvailable)
                    .padding(.horizontal, 24)

                    Spacer()
                    Text("18점 도달 후 마지막 라운드까지 진행 · 동점 시 진화수 → 카드수")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .navigationDestination(isPresented: $startSingle) {
                GameView(vm: GameViewModel(mode: .single, numPlayers: singlePlayers, seed: seed))
            }
            .navigationDestination(isPresented: $openLobby) {
                OnlineLobbyView(ranked: false)
            }
        }
    }

    private var modeDesc: String {
        switch mode {
        case .single: return "혼자서 AI 2명과 대전"
        case .casual: return "온라인 일반전 — 방을 만들거나 참가"
        case .ranked: return "랭크전 — 준비 중"
        }
    }
    private var startLabel: String {
        switch mode {
        case .single: return "게임 시작"
        case .casual: return "일반전 입장"
        case .ranked: return "랭크 준비 중"
        }
    }

    @ViewBuilder
    private func pickerBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            content()
        }
    }
}

#Preview { MenuView() }
