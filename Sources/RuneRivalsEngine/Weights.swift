// 전략 가중치(권장 시작점). 튜닝 대상.

import Foundation

public struct Weights {
    public var pts = 1.0        // 점수 가치
    public var bonus = 0.6      // 보너스 할인 가치
    public var evo = 1.5        // 진화 연결 가치
    public var goal = 0.5       // 목표 테크 정렬
    public var cost = 1.0       // 획득 비용 패널티
    public var tiebreak = 0.4   // 진화 tie-breaker
    public var reserve = 0.45   // 보관 시 V_card 감쇄(즉시 효과 아님)
    public var master = 0.8     // gold 획득 가치
    public var blind = 0.15     // 비공개 보관 기댓값
}

public let WEIGHTS = Weights()

/// 사용자 정책 소프트선택 폭.
public let USER_TOP_K = 3
/// 소프트맥스 온도(높을수록 균등).
public let USER_SOFTMAX_TEMP = 0.6
