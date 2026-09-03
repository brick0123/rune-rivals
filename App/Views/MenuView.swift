// 시작 메뉴(가로 전용): 좌 브랜딩+캐릭터 / 우 모드+시작. 싱글은 나+AI2(3인) 고정.

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
                HStack(spacing: 28) {
                    branding.frame(maxWidth: .infinity)
                    controls.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 18)
            }
            .navigationDestination(isPresented: $startSingle) {
                GameView(vm: GameViewModel(mode: .single, numPlayers: singlePlayers, seed: seed))
            }
            .navigationDestination(isPresented: $openLobby) {
                OnlineLobbyView(ranked: false)
            }
        }
    }

    // 좌: 타이틀 + 대표 캐릭터
    private var branding: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("룬업")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("RUNE UP")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tracking(8)
                    .foregroundStyle(Theme.textDim)
            }
            HStack(spacing: -16) {
                ForEach(["kai", "flame_rin", "kenny", "night_rune"], id: \.self) { name in
                    Image(name)
                        .resizable().scaledToFill()
                        .frame(width: 62, height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.15)))
                        .rotationEffect(.degrees(Double.random(in: -6 ... 6)))
                }
            }
        }
    }

    // 우: 모드 선택 + 시작 버튼 + 규칙 안내
    private var controls: some View {
        VStack(spacing: 16) {
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
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))

            Button {
                guard mode.isAvailable else { return }
                switch mode {
                case .single: seed = UInt32.random(in: 1 ... UInt32.max); startSingle = true
                case .casual: openLobby = true
                case .ranked: break
                }
            } label: {
                Text(startLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(mode.isAvailable ? SwiftUI.Color("AccentColor") : Theme.surfaceHi,
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(mode.isAvailable ? .white : Theme.textDim)
            }
            .disabled(!mode.isAvailable)

            Text("18점 도달 후 마지막 라운드까지 진행 · 동점 시 진화수 → 카드수")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
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
