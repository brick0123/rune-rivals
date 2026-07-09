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
    case joined(code: String, seat: Int, isHost: Bool, roster: [RosterEntry], token: String, hostSeat: Int)
    case spectating(code: String, roster: [RosterEntry], hostSeat: Int)
    case promote(hostSeat: Int, roster: [RosterEntry])
    case roster([RosterEntry], hostSeat: Int)
    case relay(fromSeat: Int, payload: [String: Any])
    case resend
    case reconnectFail
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
    private(set) var isOpen = false

    func connect(_ url: URL) {
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        receive()
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isOpen = false
    }

    // MARK: URLSessionWebSocketDelegate (nonisolated — 델리게이트 콜백은 메인 액터 밖에서 온다)
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        Task { @MainActor in self.isOpen = true }
    }
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let code = closeCode.rawValue
        Task { @MainActor in self.isOpen = false; self.onEvent?(.closed("closed(\(code))")) }
    }

    // MARK: 수신 루프
    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure(let e):
                    self.isOpen = false
                    self.onEvent?(.closed(e.localizedDescription))
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
    func create(name: String, roomName: String) { sendRaw(["t": "create", "name": name, "roomName": roomName]) }
    func join(code: String, name: String) { sendRaw(["t": "join", "code": code, "name": name]) }
    func spectate(code: String, name: String) { sendRaw(["t": "spectate", "code": code, "name": name]) }
    func reconnect(code: String, token: String) { sendRaw(["t": "reconnect", "code": code, "token": token]) }
    func setStatus(_ status: String) { sendRaw(["t": "status", "status": status]) }
    func relay(_ payload: [String: Any]) { sendRaw(["t": "relay", "payload": payload]) }
    func leave() { sendRaw(["t": "leave"]) }
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
        case "joined":
            onEvent?(.joined(code: m["code"] as? String ?? "", seat: m["seat"] as? Int ?? -1,
                             isHost: m["isHost"] as? Bool ?? false, roster: roster(m["roster"]),
                             token: m["token"] as? String ?? "", hostSeat: m["hostSeat"] as? Int ?? 0))
        case "spectating":
            onEvent?(.spectating(code: m["code"] as? String ?? "", roster: roster(m["roster"]), hostSeat: m["hostSeat"] as? Int ?? 0))
        case "promote":
            onEvent?(.promote(hostSeat: m["hostSeat"] as? Int ?? 0, roster: roster(m["roster"])))
        case "roster":
            onEvent?(.roster(roster(m["roster"]), hostSeat: m["hostSeat"] as? Int ?? 0))
        case "relay":
            onEvent?(.relay(fromSeat: m["fromSeat"] as? Int ?? -1, payload: (m["payload"] as? [String: Any]) ?? [:]))
        case "resend": onEvent?(.resend)
        case "reconnect-fail": onEvent?(.reconnectFail)
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
