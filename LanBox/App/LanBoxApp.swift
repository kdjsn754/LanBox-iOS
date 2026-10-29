import SwiftUI

@main
struct LanBoxApp: App {
    @StateObject private var prefs = Prefs.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(prefs)
                .preferredColorScheme(prefs.colorScheme)
                .tint(Theme.accent)
        }
    }
}
