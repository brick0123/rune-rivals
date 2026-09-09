// 카카오 로그인 추상화.
// 실제 SDK 연동(KakaoSDKUser)은 네이티브 앱 키 등록 후 붙인다 —
// 그 전까진 Placeholder 가 .notConfigured 를 던져 "준비 중" 안내만 뜬다.
//
// 키가 준비되면:
//  1) SPM 으로 https://github.com/kakao/kakao-ios-sdk 추가(KakaoSDKUser, KakaoSDKAuth)
//  2) RuneRivalsApp 진입 시 KakaoSDK.initSDK(appKey: <NATIVE_APP_KEY>)
//  3) Info.plist: CFBundleURLSchemes 에 "kakao<NATIVE_APP_KEY>",
//     LSApplicationQueriesSchemes 에 kakaokompassauth, kakaolink
//  4) 아래 KakaoAuth.provider 를 실제 구현(KakaoAuthSDK)으로 교체
//  5) onOpenURL 에서 AuthController.handleOpenUrl(url:) 처리

import Foundation

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
    /// 카카오 로그인 → 액세스 토큰 반환. (실제 구현은 내부에서 MainActor 로 홉)
    func login() async throws -> String
}

/// 앱 키 미설정 상태의 기본 구현(빌드는 되지만 로그인은 안내만).
struct KakaoAuthPlaceholder: KakaoAuthProviding {
    var isConfigured: Bool { false }
    func login() async throws -> String { throw KakaoAuthError.notConfigured }
}

enum KakaoAuth {
    /// 앱 키가 준비되면 여기를 실제 SDK 구현으로 교체.
    static var provider: KakaoAuthProviding = KakaoAuthPlaceholder()
}
