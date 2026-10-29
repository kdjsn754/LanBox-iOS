import Foundation

/// 一个文件 / 文件夹条目，对应 SMB 目录里的一项
struct Entry: Identifiable, Hashable {
    enum Kind: Int, Hashable {
        case folder
        case image
        case video
        case other
    }

    let path: String          // 绝对路径，始终以 / 开头
    let name: String
    let kind: Kind
    let size: Int64
    let modified: Date?

    var id: String { path }
    var isDir: Bool { kind == .folder }

    static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif",
        "tif", "tiff", "avif", "jfif"
    ]
    static let videoExts: Set<String> = [
        "mp4", "mkv", "mov", "avi", "wmv", "flv", "webm", "m4v",
        "ts", "m2ts", "rmvb", "3gp", "mpg", "mpeg", "ogv"
    ]

    static func kindOf(name: String, isDirectory: Bool) -> Kind {
        if isDirectory { return .folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        return .other
    }

    var ext: String { (name as NSString).pathExtension.lowercased() }
}

/// 有没有子路径都在这里统一处理，避免到处写字符串拼接
enum PathUtil {
    static func normalize(_ path: String) -> String {
        if path.isEmpty { return "/" }
        var p = path.hasPrefix("/") ? path : "/" + path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func join(_ dir: String, _ name: String) -> String {
        normalize(dir == "/" ? "/\(name)" : "\(dir)/\(name)")
    }

    static func parent(of path: String) -> String? {
        let p = normalize(path)
        if p == "/" { return nil }
        let idx = p.lastIndex(of: "/") ?? p.startIndex
        let parent = String(p[p.startIndex..<idx])
        return parent.isEmpty ? "/" : parent
    }

    static func lastComponent(_ path: String) -> String {
        let p = normalize(path)
        if p == "/" { return "共享" }
        return String(p.split(separator: "/").last ?? "")
    }
}

enum Fmt {
    static func size(_ bytes: Int64) -> String {
        if bytes <= 0 { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024 && i < units.count - 1 {
            value /= 1024
            i += 1
        }
        if i == 0 { return "\(bytes) B" }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[i])
    }

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}
