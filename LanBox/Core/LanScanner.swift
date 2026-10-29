import Foundation
import Network
import Darwin

/// 局域网里 445 端口探测。iOS 上第一次跑会弹「本地网络」授权，
/// 用户点了不允许就什么都扫不到，这一点跟安卓确实不一样。
final class LanScanner: ObservableObject {
    @Published private(set) var hosts: [String] = []
    @Published private(set) var running = false
    @Published private(set) var scanned = 0
    @Published private(set) var total = 0
    @Published private(set) var message = ""

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        hosts = []
        scanned = 0
        total = 0
        message = ""
        running = true
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }

    private func run() async {
        var candidates: [String] = []
        var seen = Set<String>()
        for net in LocalNetwork.ipv4Networks() {
            for host in LocalNetwork.hosts(in: net) where seen.insert(host).inserted {
                candidates.append(host)
            }
        }

        guard !candidates.isEmpty else {
            DispatchQueue.main.async {
                self.running = false
                self.message = "没有拿到局域网地址，先确认手机连的是 Wi-Fi"
                self.task = nil
            }
            return
        }

        DispatchQueue.main.async { self.total = candidates.count }

        let batch = 24
        var index = 0
        while index < candidates.count {
            if Task.isCancelled { break }
            let slice = Array(candidates[index..<min(index + batch, candidates.count)])
            await withTaskGroup(of: String?.self) { group in
                for host in slice {
                    group.addTask {
                        let ok = await PortProbe.open(host: host, port: 445, timeout: 0.9)
                        return ok ? host : nil
                    }
                }
                for await found in group {
                    DispatchQueue.main.async {
                        self.scanned += 1
                        if let found = found, !self.hosts.contains(found) {
                            self.hosts.append(found)
                            self.hosts.sort()
                        }
                    }
                }
            }
            index += batch
        }

        DispatchQueue.main.async {
            self.running = false
            if self.hosts.isEmpty && self.message.isEmpty {
                self.message = "没扫到开放 445 端口的设备，可以直接手动填地址"
            }
            self.task = nil
        }
    }
}

enum PortProbe {
    static func open(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let guardBox = OnceBox()
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guardBox.once {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    guardBox.once {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guardBox.once {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

/// NWConnection 的回调可能在多个线程上重复触发，continuation 只能 resume 一次
final class OnceBox {
    private let lock = NSLock()
    private var done = false

    func once(_ body: () -> Void) {
        lock.lock()
        if done {
            lock.unlock()
            return
        }
        done = true
        lock.unlock()
        body()
    }
}

enum LocalNetwork {
    struct Net {
        let address: UInt32
        let mask: UInt32
    }

    static func ipv4Networks() -> [Net] {
        var result: [Net] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let ifa = current.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo") {
                    let address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                    }
                    var mask: UInt32 = 0xFFFF_FF00
                    if let maskPtr = ifa.ifa_netmask {
                        mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                        }
                    }
                    if address != 0, mask != 0 {
                        result.append(Net(address: address, mask: mask))
                    }
                }
            }
            ptr = ifa.ifa_next
        }
        return result
    }

    static func hosts(in net: Net) -> [String] {
        let network = net.address & net.mask
        let broadcast = network | ~net.mask
        guard broadcast > network + 1 else { return [] }

        var out: [String] = []
        var ip = network + 1
        while ip < broadcast && out.count < 1024 {
            out.append(string(ip))
            ip += 1
        }
        return out
    }

    static func string(_ ip: UInt32) -> String {
        let a = (ip >> 24) & 0xFF
        let b = (ip >> 16) & 0xFF
        let c = (ip >> 8) & 0xFF
        let d = ip & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}
