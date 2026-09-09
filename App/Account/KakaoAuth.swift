// 카카오 로그인 — 실제 SDK 연동(KakaoSDKUser/Auth).
// 카카오톡 앱이 있으면 앱 로그인, 없으면 카카오계정(웹) 로그인. 액세스 토큰을 서버로 넘겨 검증한다.

import Foundation
import KakaoSDKAuth
import KakaoSDKUser
import KakaoSDKCommon

enum KakaoAuthConfig {
    /// 네이티브 앱 키(공개 키 — 앱에 embed 정상). Info.plist URL 스킴 kakao<이 값> 과 일치해야 함.
    static let nativeAppKey = "d2d31930741da8e53db9be21118dc1ee"
}

enum KakaoAuthError: LocalizedError {
    case notConfigured
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "카카오 로그인 준비 중이에요 (앱 키 설정 필요)"
        case .cancelled: return "로그인을 취소했어요"
        case let .failed(m): return m
        }
    }
}

protocol KakaoAuthProviding {
    var isConfigured: Bool { get }
    /// 카카오 로그인 → 액세스 토큰 반환.
    func login() async throws -> String
}

/// 앱 키 미설정 상태의 폴백(현재는 미사용 — 실제 구현으로 대체됨).
struct KakaoAuthPlaceholder: KakaoAuthProviding {
    var isConfigured: Bool { false }
    func login() async throws -> String { throw KakaoAuthError.notConfigured }
}

/// 실제 카카오 SDK 로그인.
struct KakaoAuthSDK: KakaoAuthProviding {
    var isConfigured: Bool { true }

    func login() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                let handler: (OAuthToken?, Error?) -> Void = { token, error in
                    if let error { cont.resume(throwing: Self.map(error)); return }
                    if let token { cont.resume(returning: token.accessToken); return }
                    cont.resume(throwing: KakaoAuthError.failed("토큰을 받지 못했어요"))
                }
                if UserApi.isKakaoTalkLoginAvailable() {
                    UserApi.shared.loginWithKakaoTalk(completion: handler)   // 카카오톡 앱 로그인
                } else {
                    UserApi.shared.loginWithKakaoAccount(completion: handler) // 카카오계정(웹) 로그인
                }
            }
        }
    }

    private static func map(_ error: Error) -> KakaoAuthError {
        if let e = error as? SdkError, case let .ClientFailed(reason, msg) = e {
            if reason == .Cancelled { return .cancelled }
            return .failed(msg ?? "로그인 실패")
        }
        return .failed(error.localizedDescription)
    }
}

enum KakaoAuth {
    static var provider: KakaoAuthProviding = KakaoAuthSDK()
}
