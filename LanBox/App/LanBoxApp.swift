import SwiftUI
import UIKit

@main
struct LanBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// 捕获崩溃写进文件，侧载场景下也能拿到堆栈定位问题
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CrashCatcher.install()
        return true
    }
}

enum CrashCatcher {
    private static var previousHandler: (@convention(c) (NSException) -> Void)?

    static func install() {
        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            let log = """
            ===== LanBox Crash =====
            name: \(exception.name.rawValue)
            reason: \(exception.reason ?? "nil")
            callStack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            =========================
            """
            write(log)
            previousHandler?(exception)
        }
    }

    private static func write(_ text: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = dir?.appendingPathComponent("lanbox-crash.log") else { return }
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + "\n\n" + text).write(to: url, atomically: true, encoding: .utf8)
    }
}
