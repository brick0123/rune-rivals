// 앱 진입점.

import SwiftUI
import KakaoSDKCommon
import KakaoSDKAuth

@main
struct RuneRivalsApp: App {
    init() {
        // 카카오 로그인 SDK 초기화(네이티브 앱 키).
        KakaoSDK.initSDK(appKey: KakaoAuthConfig.nativeAppKey)
    }

    var body: some Scene {
        WindowGroup {
            MenuView()
                .preferredColorScheme(.dark)
                // 카카오톡 앱 로그인 후 되돌아오는 URL 처리.
                .onOpenURL { url in
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
        }
    }
}
