import SwiftUI
import UIKit

@main
struct LanBoxApp: App {
    @StateObject private var prefs = Prefs.shared

    init() {
        CrashCatcher.install()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(prefs)
                .preferredColorScheme(prefs.colorScheme)
                .tint(Theme.accent)
        }
    }
}

/// C 函数指针，不能捕获任何上下文，所以单独放顶层
private func lanboxCrashHandler(_ exception: NSException) {
    let log = """
    ===== LanBox Crash (NSException) =====
    name: \(exception.name.rawValue)
    reason: \(exception.reason ?? "nil")
    callStack:
    \(exception.callStackSymbols.joined(separator: "\n"))
    =========================
    """
    CrashCatcher.writeLog(log)
}

enum CrashCatcher {
    static func install() {
        NSSetUncaughtExceptionHandler(lanboxCrashHandler)
    }

    static func writeLog(_ text: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        if let url = dir?.appendingPathComponent("lanbox-crash.log") {
            let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (previous + "\n\n" + text).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
