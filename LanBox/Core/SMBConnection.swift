import Foundation
import AMSMB2

/// 登录 SMB 需要的三件套
struct SMBCredential: Codable, Hashable {
    var user: String = ""
    var password: String = ""
    var domain: String = ""

    var isEmpty: Bool { user.isEmpty && password.isEmpty && domain.isEmpty }

    /// SMB 匿名访问一般用 guest，空用户名有的服务器会直接拒绝
    var effectiveUser: String { user.isEmpty ? "guest" : user }
}

/// 一条已经建立的共享连接。
/// 用 actor 包住是因为 AMSMB2 的 manager 会串行复用同一条会话，
/// 缩略图并发读的时候必须保证 connectShare 只跑一次。
actor SMBConnection {
    nonisolated let host: String
    nonisolated let share: String

    private let manager: SMB2Manager
    private var connected = false
    private var sizeCache: [String: Int64] = [:]

    init?(host: String, share: String, credential: SMBCredential) {
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
        self.share = share
        self.manager = manager
    }

    private func ensure() async throws {
        if connected { return }
        try await manager.connectShare(name: share)
        connected = true
    }

    func ping() async throws {
        try await ensure()
        try await manager.echo()
    }

    /// 列目录。mediaOnly 为真时把非图片/视频的文件过滤掉（跟安卓版一致）
    func entries(at path: String, mediaOnly: Bool) async throws -> [Entry] {
        try await ensure()
        let dir = PathUtil.normalize(path)
        let list = try await manager.contentsOfDirectory(atPath: dir)
        var out: [Entry] = []
        out.reserveCapacity(list.count)

        for item in list {
            guard let name = item[.nameKey] as? String, !name.isEmpty, !name.hasPrefix(".") else { continue }
            let isDir = (item[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            let kind = Entry.kindOf(name: name, isDirectory: isDir)
            if mediaOnly && kind == .other { continue }

            let size: Int64
            if let n = item[.fileSizeKey] as? NSNumber {
                size = n.int64Value
            } else if let i = item[.fileSizeKey] as? Int64 {
                size = i
            } else {
                size = 0
            }
            let entry = Entry(
                path: PathUtil.join(dir, name),
                name: name,
                kind: kind,
                size: isDir ? 0 : size,
                modified: item[.contentModificationDateKey] as? Date
            )
            if !isDir && size > 0 { sizeCache[entry.path] = size }
            out.append(entry)
        }

        out.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return out
    }

    func fileSize(_ path: String) async throws -> Int64 {
        let p = PathUtil.normalize(path)
        if let cached = sizeCache[p], cached > 0 { return cached }
        try await ensure()
        let attrs = try await manager.attributesOfItem(atPath: p)
        let size: Int64
        if let n = attrs[.fileSizeKey] as? NSNumber {
            size = n.int64Value
        } else if let i = attrs[.fileSizeKey] as? Int64 {
            size = i
        } else {
            size = 0
        }
        sizeCache[p] = size
        return size
    }

    /// 读指定区间，用于视频流式播放。
    /// AMSMB2 4.x 的 `contents(atPath:range:)` 返回 AsyncThrowingStream，
    /// 得用 `for await` 逐段收，再拼成一份 Data。
    func data(at path: String, offset: UInt64, length: Int) async throws -> Data {
        try await ensure()
        let total = try await fileSize(path)
        if offset >= UInt64(max(total, 0)) { return Data() }
        let end = min(UInt64(max(total, 0)), offset + UInt64(length))
        guard end > offset else { return Data() }

        let stream: AsyncThrowingStream<Data, any Error> = manager.contents(
            atPath: PathUtil.normalize(path),
            range: offset..<end
        )
        var result = Data()
        result.reserveCapacity(Int(end - offset))
        for try await chunk in stream {
            result.append(chunk)
        }
        return result
    }

    /// 读文件开头的一段（缩略图、首帧解码用）
    func readPrefix(_ path: String, maxBytes: Int) async throws -> Data {
        let total = try await fileSize(path)
        guard total > 0 else { return Data() }
        let len = Int(min(total, Int64(maxBytes)))
        return try await data(at: path, offset: 0, length: len)
    }

    func disconnect() {
        manager.disconnectShare(completionHandler: nil)
    }

    /// 按 "host|share" 做唯一标识，给缓存用
    nonisolated var key: String { "\(host)|\(share)" }
}
