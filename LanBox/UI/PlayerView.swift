import SwiftUI
import AVFoundation
import UIKit

struct PlayerView: View {
    let connection: SMBConnection
    let entry: Entry
    let title: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()

    @State private var chrome = true
    @State private var hideTask: Task<Void, Never>?
    @State private var seekTarget: Double?
    @State private var dragStartTime: Double = 0
    @State private var brightnessStart: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurface(player: model.player)
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.16)) { chrome.toggle() }
                    if chrome { scheduleHide() }
                }

            if model.failed {
                Text("这个视频解不开，可能是编码格式不支持")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
            }

            if chrome {
                controls
            }

            if let target = seekTarget {
                Text("\(Fmt.time(target)) / \(Fmt.time(model.duration))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
        .statusBarHidden(true)
        .task {
            model.prepare(entry: entry, connection: connection)
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            model.stop()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let width = max(UIScreen.main.bounds.width, 1)
                let height = max(UIScreen.main.bounds.height, 1)
                let dx = value.translation.width
                let dy = value.translation.height

                if abs(dx) > abs(dy) {
                    if seekTarget == nil { dragStartTime = model.current }
                    let duration = max(model.duration, 0.1)
                    let delta = Double(dx / width) * min(duration, 180)
                    seekTarget = min(max(dragStartTime + delta, 0), duration)
                } else if value.startLocation.x < width / 2 {
                    if brightnessStart == nil { brightnessStart = UIScreen.main.brightness }
                    let start = brightnessStart ?? UIScreen.main.brightness
                    let next = min(max(start - dy / height, 0), 1)
                    UIScreen.main.brightness = next
                }
                if !chrome {
                    withAnimation(.easeInOut(duration: 0.12)) { chrome = true }
                }
                hideTask?.cancel()
            }
            .onEnded { _ in
                if let target = seekTarget {
                    model.seek(to: target)
                    seekTarget = nil
                }
                brightnessStart = nil
                scheduleHide()
            }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    model.togglePlay()
                    scheduleHide()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }

                Text(Fmt.time(seekTarget ?? model.current))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { seekTarget ?? model.current },
                        set: { seekTarget = $0 }
                    ),
                    in: 0...max(model.duration, 0.1),
                    onEditingChanged: { editing in
                        if !editing, let target = seekTarget {
                            model.seek(to: target)
                            seekTarget = nil
                            scheduleHide()
                        }
                    }
                )
                .tint(.white)

                Text(Fmt.time(model.duration))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if Task.isCancelled { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) { chrome = false }
            }
        }
    }
}

struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set {
            playerLayer?.player = newValue
            playerLayer?.videoGravity = .resizeAspect
        }
    }
}

final class PlayerModel: ObservableObject {
    let player = AVPlayer()

    @Published var isPlaying = false
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var failed = false

    private var loader: SMBResourceLoader?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?

    func prepare(entry: Entry, connection: SMBConnection) {
        guard let url = SMBResourceLoader.url(for: entry) else {
            failed = true
            return
        }

        let resourceLoader = SMBResourceLoader(conn: connection, path: entry.path)
        loader = resourceLoader

        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(resourceLoader, queue: DispatchQueue(label: "lanbox.asset-loader"))
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player.replaceCurrentItem(with: item)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            self.current = seconds.isFinite ? seconds : 0
        }

        statusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if observed.status == .failed {
                    self.failed = true
                }
            }
        }

        Task { [weak self] in
            if let loaded = try? await asset.load(.duration) {
                let seconds = loaded.seconds
                DispatchQueue.main.async {
                    self?.duration = seconds.isFinite ? seconds : 0
                }
            }
        }

        player.play()
        isPlaying = true
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to time: Double) {
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        current = clamped
    }

    func stop() {
        player.pause()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player.replaceCurrentItem(with: nil)
        loader = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
