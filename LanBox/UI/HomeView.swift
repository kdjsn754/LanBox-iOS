import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var prefs: Prefs

    @State private var sessionDevice: SavedDevice?
    @State private var showAddFlow = false
    @State private var editing: SavedDevice?
    @State private var showSettings = false
    @State private var deleteTarget: SavedDevice?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 8) {
                TopBar(
                    title: "LanBox",
                    subtitle: statusText,
                    leadingIcon: "chevron.left",
                    leadingAction: nil,
                    trailingIcon: "gearshape",
                    trailingAction: { showSettings = true }
                )

                if prefs.devices.isEmpty {
                    EmptyHint(
                        icon: "externaldrive.connected.to.line.below",
                        title: "还没有添加设备",
                        detail: "点下面的按钮扫描局域网，或者手动填 IP / 主机名"
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(prefs.devices) { device in
                                deviceRow(device)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }

                addButton
            }
        }
        .fullScreenCover(item: $sessionDevice) { device in
            SessionView(device: device)
        }
        .sheet(isPresented: $showAddFlow) {
            AddDeviceFlowView()
        }
        .sheet(item: $editing) { device in
            NavigationStack {
                DeviceFormView(device: device, onFinish: { editing = nil })
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .confirmationDialog(
            deleteTarget.map { "删除「\($0.displayName)」？" } ?? "",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除连接", role: .destructive) {
                if let target = deleteTarget {
                    prefs.remove(host: target.host)
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("只删掉手机上的记录，服务器上的文件不受影响")
        }
    }

    private var statusText: String {
        prefs.devices.isEmpty ? "未添加设备" : "共 \(prefs.devices.count) 个连接"
    }

    private func deviceRow(_ device: SavedDevice) -> some View {
        Button {
            sessionDevice = device
        } label: {
            HStack(spacing: 12) {
                IconChip(systemName: "externaldrive.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(device.subtitle)
                        .font(.system(size: 12))
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
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editing = device
            } label: {
                Label("编辑连接", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget = device
            } label: {
                Label("删除连接", systemImage: "trash")
            }
        }
    }

    private var addButton: some View {
        Button {
            showAddFlow = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加设备")
                        .font(.system(size: 15, weight: .semibold))
                    Text("扫描局域网，或手动输入地址")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.82))
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 62)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
