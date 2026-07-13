// 간단한 효과음 재생기. 번들의 사운드를 미리 로드해 낮은 지연으로 재생.

import AVFoundation

enum SoundPlayer {
    // 이름별 플레이어 캐시(미리 prepare) — 빠른 연속 탭 시 재생 시작만 리셋.
    nonisolated(unsafe) private static var players: [String: AVAudioPlayer] = [:]

    static func play(_ name: String, ext: String = "mp3", volume: Float = 1.0) {
        let key = "\(name).\(ext)"
        let player: AVAudioPlayer?
        if let cached = players[key] {
            player = cached
        } else if let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let p = try? AVAudioPlayer(contentsOf: url) {
            p.prepareToPlay()
            players[key] = p
            player = p
        } else {
            player = nil
        }
        player?.volume = volume
        player?.currentTime = 0
        player?.play()
    }
}
