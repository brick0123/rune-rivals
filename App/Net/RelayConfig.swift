// 온라인 릴레이 서버 설정.
import Foundation

enum RelayConfig {
    /// 배포된 공개 릴레이(Render 무료). 각자 인터넷에서 이 주소로 접속.
    static let defaultURL = URL(string: "wss://rune-rivals-relay.onrender.com")!
    /// 로컬 테스트용(같은 망): ws://<맥 IP>:5178
    static func local(host: String, port: Int = 5178) -> URL { URL(string: "ws://\(host):\(port)")! }
}
