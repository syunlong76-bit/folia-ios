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
    var onDismiss: () -> Void

    /// 拖动进度条防抖锁定状态。
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

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
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if !renderCenter.isFullPlayerOpen {
                            bridge.webView.isHidden = true
                        }
                    }
                }
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
