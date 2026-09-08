// 온라인 릴레이 서버 설정.
import Foundation

enum RelayConfig {
    /// 배포된 공개 릴레이(GCP 서울 VM, 상시가동·저지연). 각자 인터넷에서 이 주소로 접속.
    static let defaultURL = URL(string: "wss://34.64.100.222.sslip.io")!
    /// 로컬 테스트용(같은 망): ws://<맥 IP>:5178
    static func local(host: String, port: Int = 5178) -> URL { URL(string: "ws://\(host):\(port)")! }
}
