# LanBox (iOS)

LanBox 的 iOS 移植版 —— 局域网 SMB 客户端：浏览 NAS/Windows 共享里的图片和视频，看图可双指缩放，视频支持手势控制（左半边调亮度、右半边调音量、横向拖动进度）。

与安卓版对齐的功能：

- 连接管理：手动填 IP/主机名 + 共享名 + 账号密码；局域网扫描（445 端口并发探测）
- 浏览页：网格缩略图、目录导航、只看图片视频开关、每行列数可调
- 看图页：双指缩放 / 双击放大 / 放大后拖动平移（基于 UIScrollView，手感稳）
- 视频播放：AVPlayer + 自定义 `AVAssetResourceLoaderDelegate`，从 SMB 按区间流式读，不用先整段下载；左亮度 / 右音量 / 横拖进度
- 深浅色主题、缩略图两级缓存（内存 + 磁盘）

技术栈：**SwiftUI + AMSMB2（libsmb2 封装）+ XcodeGen**。

---

## 在 GitHub 上打包 IPA

本仓库已经配好 Actions，**推送到 `main` 分支就会自动构建**，也可以手动触发：

1. 把这个目录 push 到一个 GitHub 仓库
2. 进仓库 **Actions** 页，点 `build-ipa` → **Run workflow**（或直接 push 触发）
3. 等构建完成，在构建详情页的 **Artifacts** 里下载 `LanBox-unsigned-ipa`

产物是**未签名**的 ipa（`CODE_SIGNING_ALLOWED=NO`），适合用 TrollStore / AltStore / 自签工具装到越狱或自己的设备。

### 本地构建（有 Mac + Xcode 时）

```bash
brew install xcodegen
xcodegen generate
open LanBox.xcodeproj    # 在 Xcode 里选好签名团队直接跑
```

### 关键说明

- **AMSMB2 固定 4.0.3**：这是修复 Swift 6.2 构建问题的版本，3.x 在 Xcode 16 / Swift 6 下编译不过。
- **流式读**：AMSMB2 4.x 的 `contents(atPath:range:)` 返回 `AsyncThrowingStream`，`SMBConnection.data` 里用 `for await` 逐段拼接，这是视频播放和缩略图读区的关键。
- **本地网络权限**：iOS 上首次扫描会弹「本地网络」授权，用户允许后才能发现设备；这一点跟安卓不同。

### 目录结构

```
LanBox-iOS/
├── project.yml              # XcodeGen 工程描述
├── LanBox/
│   ├── App/                 # 入口 + 主题
│   ├── Core/                # SMB 连接、扫描、缩略图、凭证、播放加载器
│   ├── Models/              # Entry、路径工具、格式化
│   └── UI/                  # 首页 / 扫描 / 浏览 / 看图 / 播放 / 设置
└── .github/workflows/       # 自动打包 ipa
```

> AMSMB2 静态链了 LGPL v2.1 的 libsmb2。自用 / 侧载没问题；如果要上 App Store，需要按 LGPL 要求动态链接。
