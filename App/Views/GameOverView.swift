// 게임 종료: 순위(점수 → 진화수 → 카드수 tiebreak).

import SwiftUI

struct GameOverView: View {
    @Bindable var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            SwiftUI.Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("게임 종료").font(.largeTitle.weight(.black)).foregroundStyle(.white)
                if let w = vm.winner {
                    Text("🏆 \(vm.playerNames[w]) 승리!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.yellow)
                }

                VStack(spacing: 8) {
                    ForEach(Array(vm.ranking.enumerated()), id: \.offset) { rank, idx in
                        let p = vm.state.players[idx]
                        HStack {
                            Text("\(rank + 1)").font(.headline.weight(.black))
                                .foregroundStyle(rank == 0 ? .yellow : Theme.textDim)
                                .frame(width: 26)
                            Text(vm.playerNames[idx]).font(.headline).foregroundStyle(.white)
                            Spacer()
                            Label("\(vm.points(idx))", systemImage: "star.fill").foregroundStyle(.yellow)
                            Label("\(p.evolutions)", systemImage: "arrow.up.circle.fill").foregroundStyle(.cyan)
                            Label("\(p.scored.count)", systemImage: "rectangle.stack.fill").foregroundStyle(Theme.textDim)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(rank == 0 ? Theme.surfaceHi : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 8)

                Button {
                    dismiss()
                } label: {
                    Text("메뉴로").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            .padding(24)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1)))
            .padding(30)
        }
    }
}
