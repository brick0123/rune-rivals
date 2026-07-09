// 앱 진입점.

import SwiftUI

@main
struct RuneRivalsApp: App {
    var body: some Scene {
        WindowGroup {
            MenuView()
                .preferredColorScheme(.dark)
        }
    }
}
