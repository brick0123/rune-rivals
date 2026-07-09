// 시작 메뉴: 모드(AI/핫시트) + 인원(2~4) 선택 → 게임 시작.

import SwiftUI
import RuneRivalsEngine

struct MenuView: View {
    @State private var mode: GameMode = .single
    @State private var numPlayers: Int = 4
    @State private var start = false
    @State private var seed: UInt32 = 1

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

                    VStack(alignment: .leading, spacing: 18) {
                        pickerBlock(title: "모드") {
                            Picker("", selection: $mode) {
                                ForEach(GameMode.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.segmented)
                        }
                        pickerBlock(title: "인원") {
                            Picker("", selection: $numPlayers) {
                                ForEach(2...4, id: \.self) { Text("\($0)인").tag($0) }
                            }.pickerStyle(.segmented)
                        }
                    }
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24)

                    Button {
                        guard mode.isAvailable else { return }
                        seed = UInt32.random(in: 1...UInt32.max)
                        start = true
                    } label: {
                        Text(mode.isAvailable ? "게임 시작" : "온라인 준비 중")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(mode.isAvailable ? Color.accentColor : Theme.surfaceHi,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(mode.isAvailable ? .white : Theme.textDim)
                    }
                    .disabled(!mode.isAvailable)
                    .padding(.horizontal, 24)

                    Text(mode == .single ? "나 vs AI \(numPlayers - 1)명" : "온라인 대전은 준비 중입니다")
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Text("18점 도달 후 마지막 라운드까지 진행 · 동점 시 진화수 → 카드수")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .navigationDestination(isPresented: $start) {
                GameView(vm: GameViewModel(mode: mode, numPlayers: numPlayers, seed: seed))
                    .navigationBarBackButtonHidden(false)
            }
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
