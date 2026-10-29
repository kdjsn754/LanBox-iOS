import SwiftUI

struct SMBOpError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// 会话：先把共享确定下来，再把连接交给浏览页
struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    let device: SavedDevice

    @StateObject private var model = SessionModel()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
        .task { await model.open(device: device) }
    }

    @ViewBuilder
    private var content: some View {
        if let connection = model.connection {
            BrowserView(
                connection: connection,
                title: device.displayName,
                onExit: { dismiss() }
            )
        } else if model.loading {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在连接 \(device.host)…")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.shares.isEmpty {
            sharePicker
        } else {
            errorView
        }
    }

    private var sharePicker: some View {
        VStack(spacing: 0) {
            TopBar(
                title: "选择共享",
                subtitle: device.host,
                leadingIcon: "chevron.left",
                leadingAction: { dismiss() },
                trailingIcon: nil,
                trailingAction: nil
            )
            List(model.shares, id: \.self) { share in
                Button {
                    Task { await model.connect(share: share) }
                } label: {
                    HStack(spacing: 12) {
                        IconChip(systemName: "folder.fill")
                        Text(share)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.text)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.faint)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            EmptyHint(
                icon: "wifi.exclamationmark",
                title: "连不上 \(device.displayName)",
                detail: model.error ?? "检查设备是否开机、SMB2/SMB3 是否开启"
            )
            HStack(spacing: 10) {
                Button("返回") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Button("重试") {
                    Task { await model.connect(share: device.share) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

final class SessionModel: ObservableObject {
    @Published var connection: SMBConnection?
    @Published var shares: [String] = []
    @Published var loading = true
    @Published var error: String?

    private var host: String = ""
    private var credential = SMBCredential()

    func open(device: SavedDevice) async {
        host = device.host
        credential = Prefs.shared.credential(for: device.host)
        await connect(share: device.share)
    }

    func connect(share: String) async {
        DispatchQueue.main.async {
            self.loading = true
            self.error = nil
            self.connection = nil
        }

        do {
            var resolved = share.trimmingCharacters(in: .whitespacesAndNewlines)
            if resolved.isEmpty {
                guard let server = SMBServer(host: host, credential: credential) else {
                    throw SMBOpError("地址格式不对")
                }
                let list = try await server.shares()
                if list.count == 1 {
                    resolved = list[0]
                } else if list.isEmpty {
                    throw SMBOpError("这台设备上没有可用的共享")
                } else {
                    DispatchQueue.main.async {
                        self.shares = list
                        self.loading = false
                    }
                    return
                }
            }

            guard let conn = ConnectionPool.shared.connection(host: host, share: resolved, credential: credential) else {
                throw SMBOpError("连接初始化失败")
            }
            try await conn.ping()

            DispatchQueue.main.async {
                self.connection = conn
                self.shares = []
                self.loading = false
            }
        } catch {
            let message = Self.describe(error)
            DispatchQueue.main.async {
                self.error = message
                self.loading = false
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let op = error as? SMBOpError { return op.message }
        let text = error.localizedDescription
        if text.isEmpty {
            return "连接失败，检查地址、账号，以及 NAS 是否开了 SMB2/SMB3"
        }
        return "连接失败：\(text)"
    }
}
