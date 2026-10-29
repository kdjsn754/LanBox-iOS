import UIKit
import ImageIO

enum ImageLoader {
    /// 从原始字节里解出一张降到 maxPixel 的图，避免把 4000 万像素的照片整个读进内存
    static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 32)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// 读一整张图（有上限），用于看图页
    static func full(conn: SMBConnection, path: String, maxPixel: CGFloat) async -> UIImage? {
        do {
            let data = try await conn.readPrefix(path, maxBytes: 24 << 20)
            return decode(data, maxPixel: maxPixel)
        } catch {
            return nil
        }
    }
}

/// 缩略图：内存 + 磁盘两级缓存，后台限 4 并发。
/// 安卓版踩过的坑这里先避开：失败不写盘、不重试死循环。
actor ThumbCache {
    static let shared = ThumbCache()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let concurrencyLimit = 4
    private let diskDirectory: URL

    init() {
        memory.countLimit = 300
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDirectory = base.appendingPathComponent("Thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    func thumbnail(for entry: Entry, conn: SMBConnection, pixelSize: CGFloat) async -> UIImage? {
        guard entry.kind == .image else { return nil }
        let key = cacheKey(entry: entry, conn: conn, pixelSize: pixelSize)
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let running = inflight[key] { return await running.value }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self = self else { return nil }
            return await self.produce(key: key, entry: entry, conn: conn, pixelSize: pixelSize)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image = image {
            memory.setObject(image, forKey: key as NSString)
        }
        return image
    }

    func cachedThumbnail(for entry: Entry, conn: SMBConnection, pixelSize: CGFloat) -> UIImage? {
        let key = cacheKey(entry: entry, conn: conn, pixelSize: pixelSize)
        return memory.object(forKey: key as NSString)
    }

    func clearAll() {
        memory.removeAllObjects()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 内部

    private func produce(key: String, entry: Entry, conn: SMBConnection, pixelSize: CGFloat) async -> UIImage? {
        let url = diskDirectory.appendingPathComponent(fnv(key) + ".jpg")
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }

        await acquire()
        defer { release() }

        do {
            let data = try await conn.readPrefix(entry.path, maxBytes: 12 << 20)
            guard let image = ImageLoader.decode(data, maxPixel: pixelSize) else { return nil }
            if let jpeg = image.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: url, options: .atomic)
            }
            return image
        } catch {
            return nil
        }
    }

    private func cacheKey(entry: Entry, conn: SMBConnection, pixelSize: CGFloat) -> String {
        "\(conn.key)|\(entry.path)|\(Int(pixelSize))"
    }

    private func acquire() async {
        if active < concurrencyLimit {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            // 名额直接交接给排队的人，active 保持不变
            waiters.removeFirst().resume()
        }
    }

    /// FNV-1a：String.hashValue 每次启动都会变，不能用来做文件名
    private func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
