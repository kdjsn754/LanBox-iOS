import SwiftUI

struct SavedDevice: Codable, Identifiable, Hashable {
    var host: String
    var name: String
    var share: String

    var id: String { host }
    var displayName: String { name.isEmpty ? host : name }
    var subtitle: String { share.isEmpty ? host : "\(host) · \(share)" }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let devices = "lanbox.devices"
        static let grid = "lanbox.grid"
        static let mediaOnly = "lanbox.mediaOnly"
        static let appearance = "lanbox.appearance"
    }

    @Published private(set) var devices: [SavedDevice] = []

    @Published var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Keys.grid) }
    }

    @Published var mediaOnly: Bool {
        didSet { defaults.set(mediaOnly, forKey: Keys.mediaOnly) }
    }

    /// system / light / dark
    @Published var appearance: String {
        didSet { defaults.set(appearance, forKey: Keys.appearance) }
    }

    private init() {
        let storedGrid = defaults.integer(forKey: Keys.grid)
        gridColumns = storedGrid == 0 ? 3 : storedGrid
        mediaOnly = defaults.object(forKey: Keys.mediaOnly) as? Bool ?? true
        appearance = defaults.string(forKey: Keys.appearance) ?? "system"
        loadDevices()
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - 设备

    private func loadDevices() {
        guard let data = defaults.data(forKey: Keys.devices),
              let list = try? JSONDecoder().decode([SavedDevice].self, from: data) else {
            devices = []
            return
        }
        devices = list
    }

    private func persistDevices() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        defaults.set(data, forKey: Keys.devices)
    }

    func upsert(_ device: SavedDevice) {
        var d = device
        d.host = d.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = devices.firstIndex(where: { $0.host == d.host }) {
            devices[idx] = d
        } else {
            devices.append(d)
        }
        devices.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        persistDevices()
    }

    func remove(host: String) {
        devices.removeAll { $0.host == host }
        persistDevices()
        SecretStore.delete(account: host)
        ConnectionPool.shared.drop(host: host)
    }

    // MARK: - 账号

    func credential(for host: String) -> SMBCredential {
        guard let data = SecretStore.get(host), let c = try? JSONDecoder().decode(SMBCredential.self, from: data) else {
            return SMBCredential()
        }
        return c
    }

    func saveCredential(_ credential: SMBCredential, for host: String) {
        if credential.isEmpty {
            SecretStore.delete(account: host)
            return
        }
        guard let data = try? JSONEncoder().encode(credential) else { return }
        SecretStore.set(data, for: host)
    }
}
