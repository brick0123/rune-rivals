// 릴레이 서버 WebSocket 클라이언트(URLSessionWebSocketTask).
// server/relay.mjs 프로토콜과 1:1 대응. 호스트(좌석 0)가 규칙 처리, 참가자는 액션 전송 + 스냅샷 렌더.

import Foundation

struct RoomInfo: Identifiable, Equatable {
    let code: String, name: String, players: Int, max: Int, status: String, spectators: Int
    var id: String { code }
}

struct RosterEntry: Identifiable, Equatable {
    let seat: Int, name: String, on: Bool
    var id: Int { seat }
}

enum RelayEvent {
    case rooms([RoomInfo])
    case queued(size: Int)
    case joined(code: String, seat: Int, isHost: Bool, roster: [RosterEntry], token: String, hostSeat: Int)
    case spectating(code: String, roster: [RosterEntry], hostSeat: Int)
    case promote(hostSeat: Int, roster: [RosterEntry], state: [String: Any]?)
    case roster([RosterEntry], hostSeat: Int)
    case relay(fromSeat: Int, payload: [String: Any])
    case resend
    case reconnecting        // 예기치 않게 끊겨 자동 재접속 시도 중
    case reconnectFail       // 재접속 실패(유예시간 초과/방 소멸) → 복구 불가
    case full
    case chat(seat: Int, name: String, text: String, spectator: Bool)
    case hostLeft
    case error(String)
    case closed(String)
}

@MainActor
final class RelayClient: NSObject, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    var onEvent: ((RelayEvent) -> Void)?
    var onOpen: (() -> Void)?
    private(set) var isOpen = false

    // 자동 재접속 상태(게임 도중 예기치 않게 끊기면 저장한 code/token 으로 다시 붙는다).
    private var url: URL?
    private var savedCode: String?
    private var savedToken: String?
    private var intentionalClose = false   // 사용자가 명시적으로 나감 → 재접속 안 함
    private var reconnecting = false        // 재접속 사이클 진행 중
    private var reconnectScheduled = false  // 재시도 예약됨(중복 방지)
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 1200  // 백오프 2~5초 → 게임 시간 내내 재시도(앱 포그라운드 복귀 시 리셋)

    func connect(_ url: URL) {
        self.url = url
        intentionalClose = false
        reconnecting = false
        reconnectScheduled = false
        reconnectAttempts = 0
        openSocket()
    }

    private func openSocket() {
        guard let url else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        receive()
    }

    func close() {
        intentionalClose = true
        reconnecting = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
    }

    // MARK: URLSessionWebSocketDelegate (nonisolated — 델리게이트 콜백은 메인 액터 밖에서 온다)
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        Task { @MainActor in
            self.isOpen = true
            if self.reconnecting, let code = self.savedCode, let token = self.savedToken {
                self.reconnect(code: code, token: token)   // 재접속: 토큰으로 좌석 복구 요청
            } else {
                self.onOpen?()
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let code = closeCode.rawValue
        Task { @MainActor in self.handleDown("closed(\(code))") }
    }

    // 소켓이 내려갔을 때 공통 처리: 의도적/복구불가면 .closed, 아니면 자동 재접속.
    private func handleDown(_ reason: String) {
        isOpen = false
        if intentionalClose { onEvent?(.closed(reason)); return }
        guard savedToken != nil, url != nil else { onEvent?(.closed(reason)); return }
        if reconnectScheduled { return }   // 이미 재시도 예약됨(이중 콜백 방지)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        if reconnectAttempts > maxReconnectAttempts {
            reconnecting = false; savedToken = nil
            onEvent?(.reconnectFail); return
        }
        reconnecting = true
        reconnectScheduled = true
        onEvent?(.reconnecting)
        let delay = min(2.0 + Double(reconnectAttempts) * 0.3, 5.0)   // 2→5초 백오프
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            if self.intentionalClose || !self.reconnecting { return }
            self.openSocket()   // didOpen 에서 reconnect() 전송
        }
    }

    /// 앱이 포그라운드로 돌아왔을 때 즉시 재연결 시도(백그라운드 중엔 타이머가 안 돌아 끊긴 채일 수 있음).
    func ensureConnected() {
        if isOpen || intentionalClose { return }
        guard savedToken != nil, url != nil else { return }
        reconnectAttempts = 0            // 포그라운드 복귀 → 재시도 예산 리셋
        reconnecting = true
        if !reconnectScheduled { openSocket() }
    }

    // MARK: 수신 루프
    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let e):
                    self.handleDown(e.localizedDescription)
                case .success(let msg):
                    switch msg {
                    case .string(let s): self.handle(s)
                    case .data(let d): if let s = String(data: d, encoding: .utf8) { self.handle(s) }
                    @unknown default: break
                    }
                    self.receive()
                }
            }
        }
    }

    private func sendRaw(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    // MARK: 프로토콜 송신
    func watchLobby() { sendRaw(["t": "watch-lobby"]) }
    /// 매치메이킹 큐 참가(오버워치식 자동 매칭). 성사되면 .joined 이벤트로 도착.
    func findMatch(name: String) { sendRaw(["t": "queue", "name": name]) }
    func cancelMatch() { sendRaw(["t": "dequeue"]) }
    func create(name: String, roomName: String) { sendRaw(["t": "create", "name": name, "roomName": roomName]) }
    func join(code: String, name: String) { sendRaw(["t": "join", "code": code, "name": name]) }
    func spectate(code: String, name: String) { sendRaw(["t": "spectate", "code": code, "name": name]) }
    func reconnect(code: String, token: String) { sendRaw(["t": "reconnect", "code": code, "token": token]) }
    func setStatus(_ status: String) { sendRaw(["t": "status", "status": status]) }
    func relay(_ payload: [String: Any]) { sendRaw(["t": "relay", "payload": payload]) }
    /// 명시적 나가기: 좌석 즉시 제거(재접속 안 함). leave 프레임 전송 후 소켓 종료.
    /// 멱등 — 화면 이탈 등으로 여러 번 불려도 첫 호출만 유효(leave 프레임이 나가기 전 소켓이 닫히는 레이스 방지).
    func leave() {
        if intentionalClose { return }
        intentionalClose = true
        reconnecting = false
        savedToken = nil
        sendRaw(["t": "leave"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.close() }
    }
    func leaveLobby() { sendRaw(["t": "leave-lobby"]) }
    func chat(_ text: String) { sendRaw(["t": "chat", "text": text]) }

    // MARK: 수신 파싱
    private func handle(_ s: String) {
        guard let data = s.data(using: .utf8),
              let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let t = m["t"] as? String else { return }
        switch t {
        case "rooms":
            let arr = (m["rooms"] as? [[String: Any]]) ?? []
            onEvent?(.rooms(arr.map {
                RoomInfo(code: $0["code"] as? String ?? "", name: $0["name"] as? String ?? "",
                         players: $0["players"] as? Int ?? 0, max: $0["max"] as? Int ?? 4,
                         status: $0["status"] as? String ?? "waiting", spectators: $0["spectators"] as? Int ?? 0)
            }))
        case "queued":
            onEvent?(.queued(size: m["size"] as? Int ?? 0))
        case "joined":
            let code = m["code"] as? String ?? "", tok = m["token"] as? String ?? ""
            savedCode = code
            if !tok.isEmpty { savedToken = tok }
            reconnecting = false; reconnectScheduled = false; reconnectAttempts = 0   // (재)접속 성공
            onEvent?(.joined(code: code, seat: m["seat"] as? Int ?? -1,
                             isHost: m["isHost"] as? Bool ?? false, roster: roster(m["roster"]),
                             token: tok, hostSeat: m["hostSeat"] as? Int ?? 0))
        case "spectating":
            onEvent?(.spectating(code: m["code"] as? String ?? "", roster: roster(m["roster"]), hostSeat: m["hostSeat"] as? Int ?? 0))
        case "promote":
            onEvent?(.promote(hostSeat: m["hostSeat"] as? Int ?? 0, roster: roster(m["roster"]),
                              state: m["state"] as? [String: Any]))
        case "roster":
            onEvent?(.roster(roster(m["roster"]), hostSeat: m["hostSeat"] as? Int ?? 0))
        case "relay":
            onEvent?(.relay(fromSeat: m["fromSeat"] as? Int ?? -1, payload: (m["payload"] as? [String: Any]) ?? [:]))
        case "resend": onEvent?(.resend)
        case "reconnect-fail":
            reconnecting = false; savedToken = nil   // 토큰 무효 → 더 이상 자동 재접속 안 함
            onEvent?(.reconnectFail)
        case "full": onEvent?(.full)
        case "chat":
            onEvent?(.chat(seat: m["seat"] as? Int ?? -1, name: m["name"] as? String ?? "",
                           text: m["text"] as? String ?? "", spectator: m["spectator"] as? Bool ?? false))
        case "host-left": onEvent?(.hostLeft)
        case "err": onEvent?(.error(m["msg"] as? String ?? "오류"))
        default: break
        }
    }

    private func roster(_ any: Any?) -> [RosterEntry] {
        ((any as? [[String: Any]]) ?? []).map {
            RosterEntry(seat: $0["seat"] as? Int ?? -1, name: $0["name"] as? String ?? "", on: $0["on"] as? Bool ?? true)
        }
    }
}
