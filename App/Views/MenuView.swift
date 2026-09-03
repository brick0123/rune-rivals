// 시작 메뉴(가로 전용): 좌 히어로(전설 카드 부채꼴 + 룬) / 우 모드·시작. 카드+룬 수집 게임 느낌.

import SwiftUI

struct MenuView: View {
    @State private var mode: GameMode = .single
    @State private var startSingle = false
    @State private var openLobby = false
    @State private var seed: UInt32 = 1

    /// 싱글 기본 인원(나 + AI 2). 최대 3인.
    private let singlePlayers = 3

    /// 히어로에 전시할 전설 카드(부채꼴).
    private var heroCards: [CardDef] {
        ["red_nova", "nika", "void_aegis"].compactMap { rom in
            CARDS.first { $0.romanized == rom }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                // 은은한 룬 글로우 배경
                RadialGradient(colors: [SwiftUI.Color(red: 0.30, green: 0.20, blue: 0.55).opacity(0.55), .clear],
                               center: .init(x: 0.36, y: 0.42), startRadius: 20, endRadius: 460)
                    .ignoresSafeArea()

                HStack(spacing: 24) {
                    hero.frame(maxWidth: .infinity)
                    controls.frame(width: 360)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .navigationDestination(isPresented: $startSingle) {
                GameView(vm: GameViewModel(mode: .single, numPlayers: singlePlayers, seed: seed))
            }
            .navigationDestination(isPresented: $openLobby) {
                OnlineLobbyView(ranked: false)
            }
        }
    }

    // 좌: 타이틀 + 전설 카드 부채꼴 + 룬 오브
    private var hero: some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text("룬업")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("RUNE UP")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .tracking(9)
                    .foregroundStyle(Theme.textDim)
            }
            cardFan
            runeRow
            Text("룬을 모아 전설의 카드를 얻고 진화시켜라")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textDim)
        }
    }

    // 전설 카드 3장 부채꼴(가운데 정면, 좌우 기울임)
    private var cardFan: some View {
        ZStack {
            ForEach(Array(heroCards.enumerated()), id: \.offset) { i, card in
                let d = CGFloat(i - 1)
                CardView(card: card, width: 116)
                    .rotationEffect(.degrees(Double(d) * 9))
                    .offset(x: d * 78, y: abs(d) * 8)
                    .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
                    .zIndex(d == 0 ? 1 : 0)
            }
        }
        .frame(height: 182)
    }

    // 룬 오브(코인) 한 줄 — 수집 토큰 느낌
    private var runeRow: some View {
        HStack(spacing: 9) {
            ForEach(BALL_COLORS, id: \.self) { bc in
                Ball(color: bc, size: 30, style: .coinRim)
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
