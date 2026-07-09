// 하단 액션 바: take3 확인 / 진화 선택 / AI 대기 표시.

import SwiftUI

struct ActionBarView: View {
    @Bindable var vm: GameViewModel

    var body: some View {
        Group {
            switch vm.phase {
            case .main:      mainBar
            case .evolve:    evolveBar
            case .aiThinking: aiBar
            case .gameOver:  EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: vm.phase)
    }

    // 구슬 선택 확인 + 안내
    private var mainBar: some View {
        HStack(spacing: 10) {
            if vm.selectedColors.isEmpty {
                Text("구슬을 탭해 3개 선택 · ×2로 같은 색 2개 · 카드를 탭해 획득/보관")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 5) {
                    ForEach(Array(vm.selectedColors.enumerated()), id: \.offset) { _, c in
                        Ball(color: BallColor(rawValue: c.rawValue)!, size: 26)
                    }
                }
                Spacer()
                Button("취소") { vm.selectedColors = [] }
                    .buttonStyle(.bordered).tint(.gray)
                Button("가져오기") { vm.confirmTake3() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canConfirmTake3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    // 진화 후보
    private var evolveBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("진화 (턴당 1회)").font(.subheadline.weight(.bold)).foregroundStyle(.cyan)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(vm.pendingEvolutions.enumerated()), id: \.offset) { _, e in
                        Button {
                            vm.applyEvolutionChoice(e)
                        } label: {
                            let s = cardOf(e.sourceId), t = cardOf(e.targetId)
                            HStack(spacing: 4) {
                                Text(s.name).font(.caption2)
                                Image(systemName: "arrow.right").font(.system(size: 9))
                                Text(t.name).font(.caption.weight(.bold))
                                Text("+\(t.points - s.points)").font(.caption2).foregroundStyle(.yellow)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Theme.surfaceHi, in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    Button("진화 안 함") { vm.skipEvolution() }
                        .font(.caption).buttonStyle(.bordered).tint(.gray)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var aiBar: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("\(vm.playerNames[vm.state.currentPlayer]) 생각 중…")
                .font(.subheadline).foregroundStyle(.white)
            Spacer()
            if !vm.lastMessage.isEmpty {
                Text(vm.lastMessage).font(.caption).foregroundStyle(Theme.textDim).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
