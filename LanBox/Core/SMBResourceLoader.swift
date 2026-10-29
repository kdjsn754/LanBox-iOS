import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// 让 AVPlayer 直接从 SMB 按区间读，不用先把整个视频下到本地。
/// 思路跟安卓版的本地 HTTP 流服务一样：播放器要哪一段就喂哪一段。
final class SMBResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "lanboxsmb"

    private let conn: SMBConnection
    private let path: String
    private var size: Int64 = 0
    private var contentType: String?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let lock = NSLock()

    init(conn: SMBConnection, path: String) {
        self.conn = conn
        self.path = path
        self.contentType = UTType(filenameExtension: (path as NSString).pathExtension)?.identifier
        super.init()
    }

    /// 用自定义 scheme 拼一个播放地址，AVURLAsset 才会把请求交给 delegate
    static func url(for entry: Entry) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "smb"
        components.path = entry.path.hasPrefix("/") ? entry.path : "/" + entry.path
        return components.url
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let id = ObjectIdentifier(loadingRequest)
        let task = Task { [weak self] in
            await self?.fulfill(loadingRequest)
        }
        lock.lock()
        tasks[id] = task
        lock.unlock()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let id = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
    }

    private func fulfill(_ request: AVAssetResourceLoadingRequest) async {
        do {
            if size <= 0 {
                size = try await conn.fileSize(path)
            }
            if let info = request.contentInformationRequest {
                info.contentLength = size
                info.isByteRangeAccessSupported = true
                info.contentType = contentType
            }
            if let dataRequest = request.dataRequest {
                var offset = dataRequest.requestedOffset
                let end = min(size, offset + Int64(dataRequest.requestedLength))
                let chunkSize: Int64 = 1 << 20

                while offset < end {
                    if Task.isCancelled { return }
                    let length = Int(min(chunkSize, end - offset))
                    let data = try await conn.data(at: path, offset: UInt64(offset), length: length)
                    if data.isEmpty { break }
                    dataRequest.respond(with: data)
                    offset += Int64(data.count)
                }
            }
            request.finishLoading()
        } catch {
            request.finishLoading(with: error)
        }
    }
}
