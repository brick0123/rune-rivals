// 게임 방법 / 규칙 안내. 처음 온 플레이어를 위한 룰 설명(스크롤).

import SwiftUI

struct HowToPlayView: View {
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // 헤더
                HStack {
                    Text("게임 방법").font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textDim).frame(width: 32, height: 32)
                            .background(Theme.surfaceHi, in: Circle())
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        section("🎯", "목표", [
                            "누군가 **18점**을 넘으면 그 라운드까지 진행하고 게임이 끝나요.",
                            "가장 높은 점수가 승리! 동점이면 **진화 수 → 카드 수**로 가려요.",
                        ])
                        section("🎮", "내 턴에 하나 선택", [
                            "**룬 집기** — 서로 다른 색 **3개**, 또는 같은 색 **2개**",
                            "**카드 구매** — 룬을 내고 카드 획득 → 승점 + 그 색 **영구 보너스**",
                            "**카드 찜** — 카드 1장 예약(최대 3장) + **마스터 룬** 획득",
                            "**블라인드 찜** — 덱 맨 위 카드를 비공개로 찜(상대는 못 봄)",
                        ])
                        section("💎", "룬 (색)", [
                            "기본 5색 룬으로 카드를 사요.",
                            "**마스터 룬**은 만능 — 아무 색이나 대체할 수 있어요. (찜하면 얻어요)",
                        ])
                        section("🃏", "카드 보너스 (핵심)", [
                            "카드를 사면 그 색을 **영구히 1개 가진 셈**이에요.",
                            "카드가 쌓일수록 더 비싼 카드를 **싸게** 살 수 있어요 → 엔진이 굴러가요.",
                        ])
                        section("⬆️", "진화", [
                            "조건을 채우면 카드를 **상위 카드로 진화** → 추가 승점을 얻어요.",
                        ])
                        section("⏱️", "시간 제한", [
                            "턴당 **30초**. 넘기면 자동 패스돼요. (10초 남으면 알림음)",
                        ])
                        section("🌐", "온라인 일반전", [
                            "매칭되면 **2~3인 실시간 대전**이에요.",
                            "상대가 잠깐 끊겨도 그 자리에서 이어져요. (게임 끝날 때까지 재접속 가능)",
                        ])
                        Text("팁: 처음엔 싱글(AI)로 몇 판 해보면 금방 익숙해져요!")
                            .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 24)
                }
            }
        }
    }

    private func section(_ icon: String, _ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(icon).font(.system(size: 18))
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            }
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundStyle(Theme.textDim)
                    Text(md(line)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1))
    }

    // **굵게** 마크다운을 AttributedString 으로.
    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
