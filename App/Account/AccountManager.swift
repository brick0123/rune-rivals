// 카카오 로그인 계정 상태 + 릴레이 계정 API 클라이언트.
// 로그인/닉네임은 서버(릴레이)가 카카오 토큰을 검증하고 accounts 테이블로 관리한다.

import Foundation
import Observation

@MainActor
@Observable
final class AccountManager {
    static let shared = AccountManager()

    private(set) var userId: String?
    private(set) var nickname: String?
    var isLoggedIn: Bool { userId != nil && nickname != nil }

    private init() {
        userId = UserDefaults.standard.string(forKey: "acct.userId")
        nickname = UserDefaults.standard.string(forKey: "acct.nickname")
    }

    // 릴레이 REST 베이스(wss → https 로 스킴 교체).
    private var httpBase: String {
        var c = URLComponents(url: RelayConfig.defaultURL, resolvingAgainstBaseURL: false)!
        c.scheme = (RelayConfig.defaultURL.scheme == "wss") ? "https" : "http"
        return (c.url?.absoluteString ?? "https://34.64.100.222.sslip.io")
    }

    func logout() {
        userId = nil; nickname = nil
        UserDefaults.standard.removeObject(forKey: "acct.userId")
        UserDefaults.standard.removeObject(forKey: "acct.nickname")
    }

    private func save(userId: String, nickname: String) {
        self.userId = userId; self.nickname = nickname
        UserDefaults.standard.set(userId, forKey: "acct.userId")
        UserDefaults.standard.set(nickname, forKey: "acct.nickname")
    }

    /// 기본 닉네임: 영문 소문자 5 + 숫자 2 (예: "abcde12").
    static func randomNickname() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let digits = "0123456789"
        let l = (0..<5).map { _ in letters.randomElement()! }
        let d = (0..<2).map { _ in digits.randomElement()! }
        return String(l) + String(d)
    }

    // MARK: - 서버 호출

    struct CheckResult { let available: Bool; let reason: String }

    /// 닉네임 사용 가능 여부(타이핑마다 호출). 서버가 형식검증 + 중복확인.
    func checkNickname(_ name: String) async -> CheckResult {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(httpBase)/nickname/check?name=\(q)") else {
            return CheckResult(available: false, reason: "확인 실패")
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return CheckResult(available: j?["available"] as? Bool ?? false,
                               reason: j?["reason"] as? String ?? "")
        } catch { return CheckResult(available: false, reason: "확인 실패") }
    }

    enum LoginOutcome: Equatable { case registered, needsNickname, failed(String) }

    /// 카카오 액세스 토큰으로 로그인. 기존 회원이면 저장 + .registered, 신규면 .needsNickname.
    func loginWithKakao(accessToken: String) async -> LoginOutcome {
        guard let resp = await post("/auth/kakao", ["accessToken": accessToken]) else { return .failed("네트워크 오류") }
        guard resp["ok"] as? Bool == true else { return .failed(resp["error"] as? String ?? "인증 실패") }
        if resp["registered"] as? Bool == true,
           let id = resp["userId"] as? String, let n = resp["nickname"] as? String {
            save(userId: id, nickname: n); return .registered
        }
        return .needsNickname
    }

    enum RegisterOutcome: Equatable { case success; case failure(String) }

    /// 신규 회원 닉네임 확정. 성공 시 계정 저장.
    func register(accessToken: String, nickname: String) async -> RegisterOutcome {
        guard let resp = await post("/auth/register", ["accessToken": accessToken, "nickname": nickname]) else {
            return .failure("네트워크 오류")
        }
        if resp["ok"] as? Bool == true,
           let id = resp["userId"] as? String, let n = resp["nickname"] as? String {
            save(userId: id, nickname: n); return .success
        }
        return .failure(resp["error"] as? String ?? "가입 실패")
    }

    struct Stats: Equatable { let games: Int; let wins: Int; let losses: Int; let winRate: Double }

    /// 일반전 전적 조회(내 닉네임).
    func fetchStats() async -> Stats? {
        guard let nick = nickname else { return nil }
        return await fetchStats(for: nick)
    }

    /// 일반전 전적 조회(임의 닉네임 — 상대 승률 표시용).
    func fetchStats(for name: String) async -> Stats? {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(httpBase)/me/stats?name=\(q)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  j["ok"] as? Bool == true else { return nil }
            let rate = (j["winRate"] as? Double) ?? Double(j["winRate"] as? Int ?? 0)
            return Stats(games: j["games"] as? Int ?? 0, wins: j["wins"] as? Int ?? 0,
                         losses: j["losses"] as? Int ?? 0, winRate: rate)
        } catch { return nil }
    }

    /// 닉네임 변경(카카오 재인증 토큰 필요). 성공 시 저장 갱신.
    func rename(accessToken: String, nickname: String) async -> RegisterOutcome {
        guard let resp = await post("/auth/rename", ["accessToken": accessToken, "nickname": nickname]) else {
            return .failure("네트워크 오류")
        }
        if resp["ok"] as? Bool == true,
           let id = resp["userId"] as? String, let n = resp["nickname"] as? String {
            save(userId: id, nickname: n); return .success
        }
        return .failure(resp["error"] as? String ?? "변경 실패")
    }

    private func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: httpBase + path) else { return nil }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }
}
