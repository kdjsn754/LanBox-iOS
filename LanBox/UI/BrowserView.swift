import SwiftUI

struct ViewerContext: Identifiable {
    let id = UUID()
    let items: [Entry]
    let index: Int
}

struct BrowserView: View {
    @EnvironmentObject private var prefs: Prefs

    let connection: SMBConnection
    let title: String
    let onExit: () -> Void

    @State private var path: String = "/"
    @State private var entries: [Entry] = []
    @State private var loading = true
    @State private var error: String?
    @State private var viewer: ViewerContext?
    @State private var playing: Entry?
    @State private var showSettings = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: max(2, min(prefs.gridColumns, 6)))
    }

    private var cellSide: CGFloat {
        let width = UIScreen.main.bounds.width - 28 - CGFloat(max(2, prefs.gridColumns) - 1) * 8
        return max(72, width / CGFloat(max(2, prefs.gridColumns)))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(
                title: currentTitle,
                subtitle: statusText,
                leadingIcon: "chevron.left",
                leadingAction: { goBack() },
                trailingIcon: "gearshape",
                trailingAction: { showSettings = true }
            )
            content
        }
        .task(id: path) { await load() }
        .fullScreenCover(item: $viewer) { context in
            ImageViewer(connection: connection, items: context.items, startIndex: context.index)
        }
        .fullScreenCover(item: $playing) { entry in
            PlayerView(connection: connection, entry: entry, title: entry.name)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = error, entries.isEmpty {
            VStack(spacing: 14) {
                EmptyHint(icon: "exclamationmark.triangle", title: "读取失败", detail: error)
                Button("重试") { Task { await load() } }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.horizontal, 60)
            }
        } else if entries.isEmpty {
            EmptyHint(
                icon: "tray",
                title: "这个文件夹是空的",
                detail: prefs.mediaOnly ? "当前只显示图片和视频，可以在设置里关掉" : nil
            )
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries) { entry in
                    cell(entry)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .refreshable { await load() }
    }

    private func cell(_ entry: Entry) -> some View {
        Button {
            open(entry)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.fill)

                    if entry.isDir {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundColor(Theme.accent)
                    } else if entry.kind == .image {
                        ThumbCell(entry: entry, connection: connection, pixelSize: cellSide * 2)
                    } else if entry.kind == .video {
                        VStack(spacing: 4) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.dim)
                            Text(Fmt.size(entry.size))
                                .font(.system(size: 9.5))
                                .foregroundColor(Theme.faint)
                        }
                    } else {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.faint)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(entry.name)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
    }

    private func open(_ entry: Entry) {
        if entry.isDir {
            path = entry.path
            return
        }
        if entry.kind == .video {
            playing = entry
            return
        }
        if entry.kind == .image {
            let images = entries.filter { $0.kind == .image }
            if let index = images.firstIndex(where: { $0.path == entry.path }) {
                viewer = ViewerContext(items: images, index: index)
            }
        }
    }

    private func goBack() {
        if let parent = PathUtil.parent(of: path) {
            path = parent
        } else {
            onExit()
        }
    }

    private var currentTitle: String {
        path == "/" ? title : PathUtil.lastComponent(path)
    }

    private var statusText: String {
        if loading { return "载入中…" }
        if entries.isEmpty { return "空文件夹" }
        return "\(entries.count) 项"
    }

    private func load() async {
        DispatchQueue.main.async {
            self.loading = true
            self.error = nil
        }
        do {
            let list = try await connection.entries(at: path, mediaOnly: prefs.mediaOnly)
            DispatchQueue.main.async {
                self.entries = list
                self.loading = false
            }
        } catch {
            let message = SessionModel.describe(error)
            DispatchQueue.main.async {
                self.error = message
                self.entries = []
                self.loading = false
            }
        }
    }
}

/// 单个缩略图格子：先看缓存，没有才去读
struct ThumbCell: View {
    let entry: Entry
    let connection: SMBConnection
    let pixelSize: CGFloat

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.faint)
            } else {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: cacheKey) {
            failed = false
            image = nil
            let loaded = await ThumbCache.shared.thumbnail(for: entry, conn: connection, pixelSize: pixelSize)
            image = loaded
            failed = (loaded == nil)
        }
    }

    private var cacheKey: String {
        "\(connection.host)|\(connection.share)|\(entry.path)|\(Int(pixelSize))"
    }
}
