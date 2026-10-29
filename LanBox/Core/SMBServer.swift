import Foundation
import AMSMB2

/// 只用来枚举一台服务器上有哪些共享的轻量连接。
/// 用户填共享名的时候省得自己去猜。
actor SMBServer {
    nonisolated let host: String
    private let manager: SMB2Manager

    init?(host: String, credential: SMBCredential) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, let url = URL(string: "smb://\(trimmedHost)") else { return nil }
        let cred = URLCredential(
            user: credential.effectiveUser,
            password: credential.password,
            persistence: .forSession
        )
        guard let manager = SMB2Manager(url: url, domain: credential.domain, credential: cred) else {
            return nil
        }
        manager.timeout = 20
        self.host = trimmedHost
        self.manager = manager
    }

    func shares() async throws -> [String] {
        do {
            let list = try await manager.listShares()
            return list.map(\.name).filter { !$0.isEmpty }
        } catch {
            // 有些服务器必须先挂到 IPC$ 才允许枚举共享
            try? await manager.connectShare(name: "IPC$")
            let list = try await manager.listShares()
            return list.map(\.name).filter { !$0.isEmpty }
        }
    }
}

/// 连接池：同一个 host+share+账号 复用一条连接，别每次翻页都重新握手
final class ConnectionPool {
    static let shared = ConnectionPool()

    private var connections: [String: SMBConnection] = [:]
    private let lock = NSLock()

    private func cacheKey(host: String, share: String, credential: SMBCredential) -> String {
        "\(host)|\(share)|\(credential.effectiveUser)|\(credential.domain)"
    }

    func connection(host: String, share: String, credential: SMBCredential) -> SMBConnection? {
        let key = cacheKey(host: host, share: share, credential: credential)
        lock.lock()
        defer { lock.unlock() }
        if let existing = connections[key] { return existing }
        guard let conn = SMBConnection(host: host, share: share, credential: credential) else { return nil }
        connections[key] = conn
        return conn
    }

    func drop(host: String) {
        lock.lock()
        let victims = connections.filter { $0.value.host == host }
        for key in victims.keys { connections.removeValue(forKey: key) }
        lock.unlock()
        for conn in victims.values { Task { await conn.disconnect() } }
    }
}
