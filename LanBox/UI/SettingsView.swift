import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var prefs: Prefs
    @Environment(\.dismiss) private var dismiss

    @State private var cleared = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $prefs.gridColumns, in: 2...6) {
                        HStack {
                            Text("每行显示")
                            Spacer()
                            Text("\(prefs.gridColumns) 个")
                                .foregroundColor(Theme.dim)
                        }
                    }
                    Toggle("只看图片和视频", isOn: $prefs.mediaOnly)
                } header: {
                    Text("浏览")
                }

                Section {
                    Picker("主题", selection: $prefs.appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("外观")
                }

                Section {
                    Button {
                        Task {
                            await ThumbCache.shared.clearAll()
                            DispatchQueue.main.async { cleared = true }
                        }
                    } label: {
                        Text(cleared ? "已清除" : "清除缩略图缓存")
                    }
                } header: {
                    Text("缓存")
                } footer: {
                    Text("缩略图会缓存在本地，清掉后下次浏览会重新生成")
                }

                Section {
                    LabeledContent("版本", value: "1.0.0")
                } header: {
                    Text("关于")
                } footer: {
                    Text("LanBox iOS 版：局域网 SMB 浏览、看图缩放、视频播放")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
