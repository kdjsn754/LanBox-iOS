import SwiftUI

/// 「添加设备」两级入口：扫描局域网 / 手动输入
struct AddDeviceFlowView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    NavigationLink {
                        ScanDevicesView(onFinish: { dismiss() })
                    } label: {
                        optionRow(
                            icon: "wifi.router",
                            title: "扫描局域网设备",
                            detail: "自动搜索同网段开放 445 端口的 NAS"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        DeviceFormView(device: nil, onFinish: { dismiss() })
                    } label: {
                        optionRow(
                            icon: "square.and.pencil",
                            title: "手动输入地址",
                            detail: "填 IP 或主机名，账号密码可以一起填"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func optionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 13) {
            IconChip(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.faint)
        }
        .cardStyle(padding: 14, radius: 16)
    }
}

/// 扫描页：只做发现和添加，删除放在首页的编辑里，避免两处都能删
struct ScanDevicesView: View {
    @EnvironmentObject private var prefs: Prefs
    let onFinish: () -> Void

    @StateObject private var scanner = LanScanner()
    @State private var addingHost: String = ""
    @State private var showForm = false

    var body: some View {
        List {
            Section {
                if scanner.hosts.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            if scanner.running {
                                ProgressView()
                            }
                            Text(scanner.running
                                 ? "正在扫描 \(scanner.scanned)/\(max(scanner.total, 1))"
                                 : (scanner.message.isEmpty ? "还没发现设备" : scanner.message))
                                .font(.system(size: 12.5))
                                .foregroundColor(Theme.faint)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 22)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(scanner.hosts, id: \.self) { host in
                    HStack(spacing: 12) {
                        IconChip(systemName: "externaldrive.fill")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(savedName(for: host))
                                .font(.system(size: 14.5, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text(host)
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.faint)
                        }
                        Spacer(minLength: 0)
                        Button {
                            addingHost = host
                            showForm = true
                        } label: {
                            Text(isSaved(host) ? "已添加" : "添加")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(isSaved(host) ? Theme.faint : Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSaved(host) ? Theme.fill : Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(scanner.hosts.isEmpty ? "扫描结果" : "已发现 \(scanner.hosts.count) 台设备")
            }
        }
        .navigationTitle("扫描局域网设备")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if scanner.running {
                        scanner.cancel()
                    } else {
                        scanner.start()
                    }
                } label: {
                    Image(systemName: scanner.running ? "stop.circle" : "arrow.clockwise")
                }
            }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.cancel() }
        .navigationDestination(isPresented: $showForm) {
            DeviceFormView(device: nil, presetHost: addingHost, onFinish: onFinish)
        }
    }

    private func isSaved(_ host: String) -> Bool {
        prefs.devices.contains { $0.host == host }
    }

    private func savedName(for host: String) -> String {
        prefs.devices.first { $0.host == host }?.displayName ?? host
    }
}

/// 手动填写的表单，添加和编辑共用
struct DeviceFormView: View {
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.dismiss) private var dismiss

    let device: SavedDevice?
    var presetHost: String?
    var onFinish: (() -> Void)?

    @State private var host: String = ""
    @State private var name: String = ""
    @State private var share: String = ""
    @State private var user: String = ""
    @State private var password: String = ""
    @State private var domain: String = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("IP 或主机名，例如 192.168.1.10", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("显示名称（留空就用地址）", text: $name)
                TextField("共享文件夹（留空则进入时列出全部）", text: $share)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("设备")
            }

            Section {
                TextField("用户名（留空按 guest 访问）", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $password)
                TextField("域（一般留空）", text: $domain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("账号")
            } footer: {
                Text("账号密码保存在系统钥匙串里，只在连接这台设备时使用")
            }
        }
        .navigationTitle(device == nil ? "添加设备" : "编辑连接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { close() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear(perform: loadOnce)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let device = device {
            host = device.host
            name = device.name
            share = device.share
            let credential = prefs.credential(for: device.host)
            user = credential.user
            password = credential.password
            domain = credential.domain
        } else if let presetHost = presetHost {
            host = presetHost
        }
    }

    private func close() {
        if let onFinish = onFinish {
            onFinish()
        } else {
            dismiss()
        }
    }

    private func save() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }
        let oldHost = device?.host
        let trimmedShare = share.trimmingCharacters(in: .whitespacesAndNewlines)

        if let oldHost = oldHost, oldHost != trimmedHost {
            prefs.remove(host: oldHost)
        }

        let saved = SavedDevice(
            host: trimmedHost,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            share: trimmedShare
        )
        prefs.upsert(saved)
        prefs.saveCredential(
            SMBCredential(user: user.trimmingCharacters(in: .whitespaces),
                          password: password,
                          domain: domain.trimmingCharacters(in: .whitespaces)),
            for: trimmedHost
        )
        close()
    }
}
