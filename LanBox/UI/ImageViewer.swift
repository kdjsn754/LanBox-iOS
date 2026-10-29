import SwiftUI
import UIKit

struct ImageViewer: View {
    let connection: SMBConnection
    let items: [Entry]
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var chrome = true

    init(connection: SMBConnection, items: [Entry], startIndex: Int) {
        self.connection = connection
        self.items = items
        _index = State(initialValue: max(0, min(startIndex, max(items.count - 1, 0))))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(items.indices, id: \.self) { i in
                    ZoomableImage(connection: connection, entry: items[i]) {
                        withAnimation(.easeInOut(duration: 0.16)) { chrome.toggle() }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if chrome {
                chromeBar
            }
        }
        .statusBarHidden(!chrome)
    }

    private var chromeBar: some View {
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

                Text(items.indices.contains(index) ? items[index].name : "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Text("\(index + 1) / \(items.count)")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Spacer()
        }
        .background(
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .ignoresSafeArea()
                .allowsHitTesting(false),
            alignment: .top
        )
    }
}

/// 用 UIScrollView 做缩放：双指、双击、放大后拖动都是系统行为，比 SwiftUI 手势稳
struct ZoomableImage: UIViewRepresentable {
    let connection: SMBConnection
    let entry: Entry
    var onTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.onTap = onTap
        view.load(connection: connection, entry: entry)
        return view
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        uiView.onTap = onTap
    }

    static func dismantleUIView(_ uiView: ZoomScrollView, coordinator: ()) {
        uiView.cancelLoading()
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var loadTask: Task<Void, Never>?
    var onTap: (() -> Void)?

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale <= 1.001 {
            imageView.frame = bounds
            contentSize = bounds.size
        }
    }

    func load(connection: SMBConnection, entry: Entry) {
        loadTask = Task { [weak self] in
            let screen = UIScreen.main.bounds
            let maxPixel = max(screen.width, screen.height) * 2
            let image = await ImageLoader.full(conn: connection, path: entry.path, maxPixel: maxPixel)
            DispatchQueue.main.async {
                guard let self = self, let image = image else { return }
                self.imageView.image = image
                self.imageView.frame = self.bounds
                self.contentSize = self.bounds.size
                self.setZoomScale(1, animated: false)
            }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView.image == nil ? nil : imageView
    }

    @objc private func handleSingleTap() {
        onTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.02 {
            setZoomScale(1, animated: true)
            return
        }
        let point = gesture.location(in: imageView)
        let target: CGFloat = 2.5
        let width = bounds.width / target
        let height = bounds.height / target
        zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2,
                        width: width, height: height), animated: true)
    }
}
