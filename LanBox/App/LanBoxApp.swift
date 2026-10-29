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

/// C 函数指针，不能捕获任何上下文，所以单独放顶层
private func lanboxCrashHandler(_ exception: NSException) {
    let log = """
    ===== LanBox Crash =====
    name: \(exception.name.rawValue)
    reason: \(exception.reason ?? "nil")
    callStack:
    \(exception.callStackSymbols.joined(separator: "\n"))
    =========================
    """
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    if let url = dir?.appendingPathComponent("lanbox-crash.log") {
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + "\n\n" + log).write(to: url, atomically: true, encoding: .utf8)
    }
}

enum CrashCatcher {
    static func install() {
        NSSetUncaughtExceptionHandler(lanboxCrashHandler)
    }
}
