// 단일 캐릭터 카드. 이미지 + 점수 + 보너스색 + 비용 pip.

import SwiftUI

struct CardView: View {
    let card: CardDef
    var width: CGFloat = 96
    var faceDown: Bool = false
    var dimmed: Bool = false

    private var height: CGFloat { width / Theme.cardAspect }

    var body: some View {
        ZStack {
            if faceDown {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(Theme.surfaceHi)
                    .overlay(
                        Image(systemName: "questionmark.diamond.fill")
                            .font(.system(size: width * 0.3))
                            .foregroundStyle(.white.opacity(0.25))
                    )
            } else {
                cardFace
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .stroke(card.bonus.keys.first.map { Theme.color($0) } ?? .gray, lineWidth: 2)
        )
        .opacity(dimmed ? 0.45 : 1)
    }

    /// 이 카드가 제공하는 보너스 색(카드 디자인의 기준색).
    private var lineColor: Color? { card.bonus.keys.first }
    private var base: SwiftUI.Color { lineColor.map { Theme.color($0) } ?? SwiftUI.Color.gray }

    // 보너스 색 바탕 + 배경 제거된 캐릭터 전체 표시(잘림 없음).
    private var cardFace: some View {
        ZStack {
            LinearGradient(
                colors: [base.opacity(0.95), base.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
            // 누끼 캐릭터 — scaledToFit 으로 전체가 보이고 투명 배경으로 바탕색이 비친다.
            Image(card.romanized)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomLeading) { costColumn }
        .overlay(alignment: .bottom) { nameBar }
    }

    private var nameBar: some View {
        Text(card.name)
            .font(.system(size: width * 0.11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, width * 0.04)
            .background(.black.opacity(0.45))
    }

    // 상단: 점수(좌) + 보너스색 점(우)
    private var topBar: some View {
        HStack {
            if card.points > 0 {
                Text("\(card.points)")
                    .font(.system(size: width * 0.22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            Spacer()
            if let bc = card.bonus.keys.first {
                Circle()
                    .fill(Theme.color(bc))
                    .frame(width: width * 0.17, height: width * 0.17)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .overlay(
                        Text("+\(card.bonus[bc] ?? 1)")
                            .font(.system(size: width * 0.1, weight: .bold))
                            .foregroundStyle(Theme.onBall(BallColor(rawValue: bc.rawValue)!))
                    )
            }
        }
        .padding(width * 0.06)
        .background(
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
        )
    }

    // 좌하단: 비용 pip 세로 나열
    private var costColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(COLORS.filter { (card.cost[$0] ?? 0) > 0 }, id: \.self) { c in
                CostPip(color: c, count: card.cost[c] ?? 0, size: width * 0.2)
            }
            if isNoble(card.tier) {
                CostPip(color: nil, count: 1, size: width * 0.2) // gold 필수
            }
        }
        .padding(width * 0.05)
    }

}

/// 비용 표시 pip: 색 원 + 숫자. color==nil 이면 gold(궁극의 룬 오브).
struct CostPip: View {
    let color: Color?
    let count: Int
    var size: CGFloat = 18

    var body: some View {
        let bc: BallColor = color.map { BallColor(rawValue: $0.rawValue)! } ?? .gold
        Text("\(count)")
            .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onBall(bc))
            .frame(width: size, height: size)
            .background(Theme.ballColor(bc), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
    }
}
