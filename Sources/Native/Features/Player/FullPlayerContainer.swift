import SwiftUI

/// 全屏播放容器（M2，native-arch.md §10）。
///
/// 原生顶栏＋底部原生 Slider 精准进度（拖动锁定 isScrubbing，松手才 seek）。
/// 常驻挂载＋位移切换：容器位移用 GeometryReader 实测高度（弃 UIScreen.main.bounds），
/// spring 动画结束后同步 webView.isHidden，离屏不进合成。
/// 展开 / 收起状态唯一来源是 RenderStateCenter.isFullPlayerOpen；
/// WebEffect WebView 本体由 WebEffectBridge 单例持有，容器只包装，不重建。
struct FullPlayerContainer: View {
    @ObservedObject var engine = PlaybackEngine.shared
    @ObservedObject var bridge = WebEffectBridge.shared
    @ObservedObject var renderCenter = RenderStateCenter.shared
    @ObservedObject var queueManager = QueueManager.shared
    var onDismiss: () -> Void

    /// 拖动进度条防抖锁定状态。
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    /// 特效面板与队列页的呈现开关（3.3 播放页收口）。
    @State private var showStylePanel = false
    @State private var showQueue = false

    /// 视觉选择（原生侧存一份，与特效面 store 经桥同步；特效面也会自己持久化）。
    @AppStorage("folia.lyricMode") private var lyricMode = "classic"
    @AppStorage("folia.backgroundMode") private var backgroundMode = "common"

    private var isOpen: Bool { renderCenter.isFullPlayerOpen }

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubTime : engine.currentTime
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底层深色底板，防止网页加载瞬间透出底层主页。
                Color.black.ignoresSafeArea()

                // 核心：Folia 纯可视化网页特效面（桥单例持有，常驻不重建）。
                WebEffectView(webView: bridge.webView)
                    .ignoresSafeArea()

                // 原生顶栏与底部精准进度控制层。
                VStack {
                    // 顶部：收起按钮 + 曲名。
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.down")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("收起播放页")

                        Spacer()

                        if let track = engine.currentTrack {
                            VStack(spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    // 底部原生进度条 +  transport（网页 transport 已剥离，这里是唯一一套）。
                    VStack(spacing: 12) {
                        if let error = queueManager.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.55))
                                .clipShape(Capsule())
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { displayedTime },
                                    set: { newValue in
                                        scrubTime = newValue
                                    }
                                ),
                                in: 0...max(engine.duration, 1),
                                onEditingChanged: { editing in
                                    isScrubbing = editing
                                    if editing {
                                        scrubTime = engine.currentTime
                                    } else {
                                        // 松手才 seek：先让桥推乐观锚点并挂起周期推送。
                                        WebEffectBridge.shared.noteSeekStarted(target: scrubTime)
                                        engine.seek(to: scrubTime)
                                    }
                                }
                            )
                            .tint(.white)

                            HStack {
                                Text(formatTime(displayedTime))
                                Spacer()
                                Text(formatTime(engine.duration))
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 44) {
                            Button {
                                QueueManager.shared.playPrevious()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                            }
                            .accessibilityLabel("上一首")

                            Button {
                                engine.togglePlayPause()
                            } label: {
                                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                            }
                            .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")

                            Button {
                                QueueManager.shared.playNext(manual: true)
                            } label: {
                                Image(systemName: "forward.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 48, height: 48)
                            }
                            .accessibilityLabel("下一首")
                        }

                        // 播放模式 / 特效切换 / 队列（3.3 收口补回的功能行）。
                        HStack {
                            Button {
                                cyclePlayMode()
                            } label: {
                                Image(systemName: playModeIcon)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 44, height: 32)
                            }
                            .accessibilityLabel("播放模式")

                            Spacer()

                            Button {
                                showStylePanel = true
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                    Text("特效")
                                }
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .frame(height: 32)
                            }
                            .accessibilityLabel("歌词特效与背景")

                            Spacer()

                            Button {
                                showQueue = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 44, height: 32)
                            }
                            .accessibilityLabel("播放队列")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            // 位移切换：容器实测高度（GeometryReader），不用 UIScreen.main.bounds。
            .offset(y: isOpen ? 0 : geo.size.height)
            .allowsHitTesting(isOpen)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isOpen)
            .onAppear {
                if !isOpen {
                    bridge.webView.isHidden = true
                }
            }
            // iOS 17 新签名 onChange：spring 动画结束后同步 webView.isHidden。
            .onChange(of: isOpen) { _, open in
                if open {
                    bridge.webView.isHidden = false
                    // 打开播放页时把原生侧的视觉选择推给特效面，保持两边一致。
                    bridge.pushVisual(lyricMode: lyricMode, backgroundMode: backgroundMode)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if !renderCenter.isFullPlayerOpen {
                            bridge.webView.isHidden = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showStylePanel) {
            StylePanelView(
                lyricMode: $lyricMode,
                backgroundMode: $backgroundMode,
                onLyricModeChange: { bridge.pushVisual(lyricMode: $0, backgroundMode: nil) },
                onBackgroundModeChange: { bridge.pushVisual(lyricMode: nil, backgroundMode: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showQueue) {
            QueueListView()
                .presentationDetents([.medium, .large])
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var playModeIcon: String {
        switch queueManager.playMode {
        case .loopAll: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    private func cyclePlayMode() {
        switch queueManager.playMode {
        case .loopAll: queueManager.playMode = .repeatOne
        case .repeatOne: queueManager.playMode = .shuffle
        case .shuffle: queueManager.playMode = .loopAll
        }
    }
}

/// 特效面板（3.3）：歌词样式 17 种 + 背景类型 5 种，id 与网页注册表同源
///（folia-major src/types/visualizerModes.ts 的 BUILTIN 清单与各 entry 的
/// labelFallback，顺序按 registry order）。选择经桥发给特效面即时生效。
private struct StylePanelView: View {
    @Binding var lyricMode: String
    @Binding var backgroundMode: String
    var onLyricModeChange: (String) -> Void
    var onBackgroundModeChange: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let lyricStyles: [(id: String, label: String)] = [
        ("sonnet", "商籁"), ("tempera", "Tempera"), ("lumiere", "绘光"),
        ("hanabi", "花火"), ("machi", "町景"), ("nebbia", "雾笺"),
        ("classic", "Luminous"), ("cadenza", "Mindscape"), ("partita", "云阶"),
        ("fume", "Fume"), ("tilt", "Tilt"), ("claddagh", "Claddagh"),
        ("monet", "Monet"), ("pendolo", "Pendolo"), ("cappella", "Cappella"),
        ("diorama", "镜台"), ("still", "Still")
    ]

    private let backgroundModes: [(id: String, label: String)] = [
        ("common", "通用"), ("latent", "潜行"), ("monet", "莫奈"),
        ("nomand", "游牧"), ("sora", "天空")
    ]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(title: "歌词样式", items: lyricStyles, selected: lyricMode) { id in
                        lyricMode = id
                        onLyricModeChange(id)
                    }
                    section(title: "背景类型", items: backgroundModes, selected: backgroundMode) { id in
                        backgroundMode = id
                        onBackgroundModeChange(id)
                    }
                }
                .padding(16)
            }
            .navigationTitle("特效")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func section(
        title: String,
        items: [(id: String, label: String)],
        selected: String,
        onPick: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(items, id: \.id) { item in
                    Button {
                        onPick(item.id)
                    } label: {
                        Text(item.label)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selected == item.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.secondary.opacity(0.12)
                            )
                            .foregroundColor(selected == item.id ? .accentColor : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// 播放队列页（3.3）：点任意一首跳过去播，当前曲高亮。
private struct QueueListView: View {
    @ObservedObject var queueManager = QueueManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(queueManager.queue.enumerated()), id: \.element.id) { index, track in
                    Button {
                        queueManager.playAtIndex(index)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(index == queueManager.currentIndex ? .bold : .regular))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if index == queueManager.currentIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("播放队列（\(queueManager.queue.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
