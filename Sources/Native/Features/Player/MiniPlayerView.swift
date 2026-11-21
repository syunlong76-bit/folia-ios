import SwiftUI
import UIKit

/// 原生悬浮迷你播放条（M2；2026-11-16 按 Folia 自带 BrowseMiniBar 对齐数值）。
///
/// (53) 工作流 H：按 Miller 定案把网页播放卡整排按钮＋设置入口搬进
/// 本组件——构成以网页源码为 oracle（folia-major
/// FloatingPlayerControls.tsx 的 ExpandedView＋CapsuleQuickActions、
/// floating-player/playerControlSlotActions.ts、UnifiedPanel 的
/// SongActions 设置入口），不是照截图猜：
///
/// - 上排（网页胶囊悬停浮出的 CapsuleQuickActions 排＋面板 SongActions
///   的设置键）：喜欢（Heart，capsuleAction）/ 打乱队列（Shuffle，
///   capsuleAction）/ 播放模式（Repeat 三态图标，原生为四档）/
///   睡眠定时（Timer，槽位动作）/ 齿轮设置入口（SongActions 的
///   Settings 键 → 现有 SettingsViewController）。
/// - 下排（网页 ExpandedView 主排）：封面＋标题区（点按展开，网页
///   TrackTitleNavigator 位）/ 上一首 / 播放暂停 / 下一首；排下沿
///   一条进度条（网页 ExpandedView 第三行 ProgressBar，点按/
///   拖动 seek）。播放列表入口不在台面（(53) H 修正）：已迁宿主
///   上方隐藏排（舞台＝顶栏排、曲目墙＝顶部 chrome 排），本组件
///   只保留 openQueue() 供宿主接线调用。
///
/// 网页有但原生无真实目标的键不放假按钮（缺项见 (53) H 报告）：
/// 星标「加入歌单」（AddToPlaylist 本体未迁）、格子「歌词样式选择器」
/// （visualizer-picker 本体未迁）、字幕设置、音量（网页本身即
/// mouse-only，iOS 系统音量接管）、命令面板 ⌘ 本体（未迁；队列面
/// 由下排列表键直达 QueuePanel 承接）、歌词时间轴（原生舞台即
/// 歌词面）、定位/回墙（墙面台头像点按定位已有等价，见 (48) 审计
/// #13/#14）。
///
/// 功能全部指向既有 API，不新造播放逻辑：喜欢 = LikesStore.toggle
/// ＋NativeDataClient.setLike 云端同步（与舞台 toggleLike 同路，
/// 失败回滚）；模式 = QueueManager.playMode 四档轮换；打乱队列 =
/// QueueManager.shuffleQueue；睡眠 = SleepTimerController 预设档
/// 轮换；列表 = QueuePanelViewController.present；设置 =
/// SettingsViewController（overFullScreen、animated: false，与墙内
/// 齿轮 wallSettingsTapped 同一呈现方式）。
///
/// 三键槽位自定义（(50) MiniBarSlotSettings）继续生效：下排
/// prev/next 按 showPrev/showNext 显隐（queue 已迁出，见上），订阅
/// .foliaMiniBarSlotsChanged 即时重读；播放键恒显（与三台既有
/// 口径一致）。MiniBarSlotSettings.swift 本文件只读不改。
///
/// 注意（集成缺口，(53) H 报告已列明）：本组件当前无宿主引用——
/// 墙/舞台三台的点播台是各自 VC 内用 MiniBarHitView 手搭的 UIKit
/// 台面（HomeWallViewController / WallPrototypeViewController /
/// StageViewController，均不在 H 的可改文件内）。本组件是整排的
/// 唯一实现面，三台接入（以 UIHostingController 替换手搭台面或
/// 按本排表逐台对齐）需父级另行授权改那三个文件后才在真机生效；
/// 三台既有定版规格（同尺寸/5 秒收起/主题/槽位）本文件零触碰、
/// 零回归。
struct MiniPlayerView: View {
    @ObservedObject var engine = PlaybackEngine.shared
    @ObservedObject var queueManager = QueueManager.shared
    var onTapExpand: () -> Void
    /// 列表/设置入口的宿主回调；nil 时走 MiniPlayerPanelPresenter
    /// 从当前 VC 链顶层 present（与三台既有呈现方式一致）。
    var onOpenQueue: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil

    @State private var isLiked = false
    @State private var sleepActive = false
    /// (62) 歌名区长按收藏弹层开关。
    @State private var showAddToPlaylist62 = false
    /// 槽位显隐重读令牌：.foliaMiniBarSlotsChanged 到达时 +1 触发重算。
    @State private var slotsVersion = 0

    var body: some View {
        if let track = engine.currentTrack {
            VStack(spacing: 2) {
                quickActionsRow(track: track)
                mainRow(track: track)
                progressRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
                        .opacity(0.85))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 12)
            .onAppear { refreshLike(trackId: track.id); refreshSleep() }
            .onChange(of: track.id) { _, newId in refreshLike(trackId: newId) }
            .onReceive(NotificationCenter.default.publisher(
                for: SleepTimerController.changedNotification)) { _ in refreshSleep() }
            .onReceive(NotificationCenter.default.publisher(
                for: .foliaMiniBarSlotsChanged)) { _ in slotsVersion += 1 }
            // (62) 歌名区长按 → 收藏到歌单弹层（与搜索页同体）。
            .sheet(isPresented: $showAddToPlaylist62) {
                MiniAddToPlaylistSheet62(track: track)
            }
        }
    }

    // MARK: - 上排（网页 CapsuleQuickActions＋设置入口）

    private func quickActionsRow(track: FoliaTrack) -> some View {
        HStack(spacing: 2) {
            // 喜欢：网页 slot like / 命令 playback-like（capsuleAction）。
            // 回显 = LikesStore 本地真源（与舞台 refreshLikeButton 同源）。
            Button {
                toggleLike(track: track)
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 17))
                    // (68) A1 状态强可视化：已喜欢 = 整钮填充
                    // 喜欢色＋白心；未喜欢维持现行（白 75%、无填充）。
                    .foregroundColor(isLiked
                        ? .white
                        : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLiked
                                ? Color(red: 1, green: 0.35, blue: 0.45)
                                : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "取消喜欢" : "喜欢")

            // 打乱队列：网页命令 playback-shuffle（capsuleAction），
            // 与槽位 shuffle 的 canShuffle 同判：队列不足 2 首禁用。
            Button {
                Breadcrumbs.log("minibar.webrow shuffleQueue")
                queueManager.shuffleQueue()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(queueManager.queue.count < 2)
            .opacity(queueManager.queue.count < 2 ? 0.35 : 1)
            .accessibilityLabel("打乱队列")

            // 播放模式：网页 slot loop（Repeat 图标随档位变、非 off
            // 高亮）。网页三档 off/all/one，原生四档（(48) #1）：
            // 顺序 off / 循环 repeat / 单曲 repeat.1 / 随机 shuffle，
            // 点按按此序轮换，写回 QueueManager.playMode（@Published
            // 回显即时刷新本排图标与高亮）。
            Button {
                cyclePlayMode()
            } label: {
                Image(systemName: playModeSymbol)
                    .font(.system(size: 16))
                    .foregroundColor(queueManager.playMode == .off
                        ? .white.opacity(0.45) : .white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放模式")

            // 睡眠定时：网页槽位 sleep-timer。点按在预设档间轮换
            // （关→10→20→30→45→60→关），生效态高亮；剩余时间精
            // 细管理仍在队列面板管理区（(48) #11）。
            Button {
                cycleSleepTimer()
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 16))
                    .foregroundColor(sleepActive ? .white : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("定时关闭")

            Spacer(minLength: 4)

            // 设置入口：网页 UnifiedPanel SongActions 右端 Settings
            // 键（onOpenSettings）。原生接现有 SettingsViewController。
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
        }
    }

    // MARK: - 下排（网页 ExpandedView 主排）

    private func mainRow(track: FoliaTrack) -> some View {
        // 槽位显隐在 builder 外读入局部量：body 的 onReceive 收到
        // .foliaMiniBarSlotsChanged 后改 slotsVersion（@State），
        // 整视图重绘时本函数重跑，读到的恒为最新 UserDefaults 值。
        _ = slotsVersion
        let showPrev = MiniBarSlotSettings.showPrev
        let showNext = MiniBarSlotSettings.showNext
        return HStack(spacing: 8) {
            // 封面＋标题区：点按展开播放页（原 onTapExpand 语义收窄
            // 到本区，避免上/下排按钮点按被容器手势连带触发展开；
            // 原实现为整条 onTapGesture，按钮与展开双触发）。
            HStack(spacing: 12) {
                ZStack {
                    MiniCoverView(artworkURL: track.artworkURL)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if engine.playbackState == .waiting {
                        ProgressView()
                            .tint(.white)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    // (62) 歌名 marquee：长标题溢出时滚动
                    // （Marquee62，只溢出才滚、缓动启停）。
                    Marquee62(text: track.title)
                        .frame(height: 18)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                // (62) 歌名区左右小箭头：与主排共存——主排
                // prev/next 显时小箭头让位（冲突以主排为准，
                // 槽位键关掉主排钮时小箭头补位）。
                if !showPrev {
                    Button {
                        QueueManager.shared.playPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 18, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("上一首（歌名区）")
                }
                if !showNext {
                    Button {
                        QueueManager.shared.playNext(manual: true)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 18, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一首（歌名区）")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapExpand() }
            // (62) 歌名区长按开收藏弹层：与 (61) 单击浮层/
            // 双击详情的调和——单击（展开）与双击语义不动，
            // 收藏走长按（与顶排星标点按开弹层同为「收藏」
            // 入口族，长按是标题区唯一未占用手势）。
            .onLongPressGesture(minimumDuration: 0.45) {
                Breadcrumbs.log("minibar.title longpress addToPlaylist")
                showAddToPlaylist62 = true
            }

            Spacer(minLength: 4)

            // 槽位三键（(50)）：显隐值已在本函数体读入局部量。
            if showPrev {
                Button {
                    QueueManager.shared.playPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一首")
            }

            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")

            if showNext {
                Button {
                    QueueManager.shared.playNext(manual: true)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }

            // 播放列表入口已按 (53) H 修正迁出本台面（宿主上方
            // 隐藏排），此处不再放钮；openQueue() 保留供宿主调用。
        }
    }

    // MARK: - 进度行（网页 ExpandedView 第三行 ProgressBar）

    private var progressRow: some View {
        GeometryReader { geo in
            let fraction = engine.duration > 0
                ? min(1, max(0, engine.currentTime / engine.duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white.opacity(0.85))
                    .frame(width: geo.size.width * fraction)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard engine.duration > 0, geo.size.width > 0 else { return }
                        let ratio = min(1, max(0, value.location.x / geo.size.width))
                        engine.seek(to: engine.duration * ratio)
                    })
        }
        .frame(height: 4)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: - 动作与回显

    private var playModeSymbol: String {
        switch queueManager.playMode {
        case .loopAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        case .off: return "repeat"
        }
    }

    private func cyclePlayMode() {
        let order: [QueueManager.PlayMode] = [.off, .loopAll, .repeatOne, .shuffle]
        let current = order.firstIndex(of: queueManager.playMode) ?? 1
        let next = order[(current + 1) % order.count]
        queueManager.playMode = next
        Breadcrumbs.log("minibar.webrow mode=\(next.rawValue)")
    }

    private func cycleSleepTimer() {
        let presets = SleepTimerController.presets
        let current = SleepTimerController.shared.activePresetMinutes ?? 0
        let index = presets.firstIndex(of: current) ?? 0
        let next = presets[(index + 1) % presets.count]
        SleepTimerController.shared.set(minutes: next)
        refreshSleep()
    }

    private func refreshSleep() {
        sleepActive = SleepTimerController.shared.isActive
    }

    private func refreshLike(trackId: String) {
        isLiked = LikesStore.shared.isLiked(trackId)
    }

    /// 与舞台 StageViewController.toggleLike 同路：本地先切换回显，
    /// 云端 setLike 失败回滚本地并重刷。
    private func toggleLike(track: FoliaTrack) {
        let id = track.id
        let newState = LikesStore.shared.toggle(id)
        isLiked = newState
        Breadcrumbs.log("minibar.webrow like id=\(id) on=\(newState)")
        Task {
            do {
                _ = try await NativeDataClient.shared.setLike(trackId: id, like: newState)
            } catch {
                LikesStore.shared.toggle(id)
                await MainActor.run { refreshLike(trackId: id) }
            }
        }
    }

    private func openQueue() {
        if let onOpenQueue {
            onOpenQueue()
        } else {
            MiniPlayerPanelPresenter.presentQueue()
        }
    }

    private func openSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            MiniPlayerPanelPresenter.presentSettings()
        }
    }
}

/// 迷你台面板呈现（宿主未注入回调时的默认路径）：从当前 key window
/// 的 VC 链顶层 present——设置页与墙内齿轮同一方式
/// （SettingsViewController、overFullScreen、animated: false）；
/// 队列面板走 QueuePanelViewController.present 的既有静态入口
/// （pageSheet、medium/large detents，内部自打 queue.panel.open）。
enum MiniPlayerPanelPresenter {

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: { $0.isKeyWindow })?
            .rootViewController ?? scene?.windows.first?.rootViewController
        else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    static func presentSettings() {
        guard let top = topViewController() else {
            Breadcrumbs.log("minibar.settings present FAIL no-top-vc")
            return
        }
        let settings = SettingsViewController()
        settings.modalPresentationStyle = .overFullScreen
        Breadcrumbs.log("minibar.settings present")
        top.present(settings, animated: false)
    }

    static func presentQueue() {
        guard let top = topViewController() else {
            Breadcrumbs.log("minibar.queue present FAIL no-top-vc")
            return
        }
        Breadcrumbs.log("minibar.queue present")
        QueuePanelViewController.present(from: top)
    }
}

/// 迷你条封面：远程 URL 走 AsyncImage；本地 file URL 走 UIImage 加载
///（不直接用 AsyncImage 加载 file URL，见 native-arch.md §7 M3 登记 ⑦）。
/// 无封面/加载中 = white/10 空块（BrowseMiniBar 原样）。
private struct MiniCoverView: View {
    let artworkURL: URL?
    @State private var fileImage: UIImage?

    var body: some View {
        ZStack {
            if let fileImage {
                Image(uiImage: fileImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = artworkURL, url.scheme != "file" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .task(id: artworkURL?.absoluteString) {
            guard let url = artworkURL, url.scheme == "file" else { return }
            fileImage = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
    }

    private var coverPlaceholder: some View {
        Color.white.opacity(0.10)
    }
}


/// (62) 收藏弹层的 SwiftUI 挂载（与搜索页 AddToPlaylistSheet
/// 同体：UINavigationController 包 AddToPlaylistViewController，
/// pageSheet 呈出）。搜索页那份为其文件私有，故此处另置一份。
private struct MiniAddToPlaylistSheet62: UIViewControllerRepresentable {
    let track: FoliaTrack

    func makeUIViewController(context: Context) -> UINavigationController {
        UINavigationController(rootViewController: AddToPlaylistViewController(track: track))
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
