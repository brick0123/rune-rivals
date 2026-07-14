// 효과음 재생기 — 낮은 지연.
// 첫 탭 지연 방지를 위해 미리 로드(prepareToPlay) + 오디오 세션 사전 활성화,
// 빠른 연속 탭 대응을 위해 플레이어 풀(라운드로빈)을 사용한다.

import AVFoundation

enum SoundPlayer {
    nonisolated(unsafe) private static var pools: [String: [AVAudioPlayer]] = [:]
    nonisolated(unsafe) private static var nextIndex: [String: Int] = [:]
    nonisolated(unsafe) private static var sessionReady = false

    private static func activateSession() {
        guard !sessionReady else { return }
        sessionReady = true
        let s = AVAudioSession.sharedInstance()
        // 다른 앱 오디오와 섞이고, 게임 효과음이므로 무음 스위치를 존중(.ambient).
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    /// 미리 로드(워밍업). 첫 탭 지연을 없애고, count 개 풀로 연속 탭 지연을 줄인다.
    static func preload(_ name: String, ext: String = "mp3", count: Int = 4) {
        activateSession()
        guard pools[name] == nil,
              let url = Bundle.main.url(forResource: name, withExtension: ext) else { return }
        var players: [AVAudioPlayer] = []
        for _ in 0..<max(1, count) {
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                players.append(p)
            }
        }
        pools[name] = players
        nextIndex[name] = 0
    }

    static func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        if pools[name] == nil { preload(name, ext: ext) }
        guard let players = pools[name], !players.isEmpty else { return }
        let i = (nextIndex[name] ?? 0) % players.count
        nextIndex[name] = i + 1
        let p = players[i]
        p.volume = volume
        p.currentTime = 0
        p.play()
    }
}
