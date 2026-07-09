// 결정론적 시드 RNG(mulberry32). 같은 시드 → 같은 게임 결과(재현/디버깅).
// AI 미리보기는 상태 복제와 함께 이 RNG 를 복제해 분기한다.
// 32비트 오버플로 연산을 &+ · &* 로 재현해 원본 TS(Math.imul, >>>0)와 동일 수열을 낸다.

import Foundation

public final class Rng {
    private var s: UInt32

    public init(seed: UInt32) {
        self.s = seed
    }

    /// 현재 내부 상태(복제용).
    public var state: UInt32 { s }

    /// [0,1) 의사난수.
    public func next() -> Double {
        s = s &+ 0x6d2b79f5
        var t = s
        t = (t ^ (t >> 15)) &* (1 | s)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double((t ^ (t >> 14))) / 4294967296.0
    }

    /// [0, max) 정수.
    public func int(_ max: Int) -> Int {
        Int(Double(next()) * Double(max))
    }

    /// [min, max] 정수(닫힌 구간).
    public func range(_ min: Int, _ max: Int) -> Int {
        min + int(max - min + 1)
    }

    public func pick<T>(_ arr: [T]) -> T {
        arr[int(arr.count)]
    }

    /// Fisher-Yates. 입력 배열을 뒤섞어 반환.
    @discardableResult
    public func shuffle<T>(_ arr: [T]) -> [T] {
        var a = arr
        var i = a.count - 1
        while i > 0 {
            let j = int(i + 1)
            a.swapAt(i, j)
            i -= 1
        }
        return a
    }

    /// 동일 상태를 갖는 복제본.
    public func clone() -> Rng {
        Rng(seed: s)
    }
}
