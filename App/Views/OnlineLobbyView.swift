// 온라인 로비(일반전) — 방 목록/생성/참가.
// 현재는 서버 연결 확인 + 자리표시. 방 대기실·네트워크 대전 UI는 다음 단계에서 RelayClient 로 연결.

import SwiftUI

struct OnlineLobbyView: View {
    let ranked: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "wifi")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text(ranked ? "랭크전" : "일반전")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
                Text("온라인 로비 구현 중")
                    .font(.headline)
                    .foregroundStyle(Theme.textDim)
                VStack(spacing: 6) {
                    Text("서버")
                        .font(.caption).foregroundStyle(Theme.textDim)
                    Text(RelayConfig.defaultURL.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

                Text("서버는 배포·동작 확인 완료. 방 목록/대기실/실시간 대전 UI를 붙이는 중입니다.")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Button("메뉴로") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(ranked ? "랭크" : "일반전")
        .navigationBarTitleDisplayMode(.inline)
    }
}
