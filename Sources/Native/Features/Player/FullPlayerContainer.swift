import SwiftUI

/// 全屏播放容器（M2 骨架 + 2026-11-16 口径收口）。
///
/// 播放页 UI 全部归 Folia 网页自带组件：底部胶囊条 FloatingPlayerControls +
/// 右下手柄玻璃面板 UnifiedPanel（封面/控制/队列/账号页签，外观区在控制
/// 页签内），走带/队列/音量/收起经 foliaNative 通道回原生引擎执行。原生侧
/// 不再画任何走带、进度与特效选择控件——3.3/3.4 的自创原生条与特效筹码表
/// 已撤（Miller 2026-11-16 定版口径：源码功能与界面原封不动，原生只接管
/// 会闪退/会卡的底层）。
///
/// 本容器只剩三件事：
/// 1. 常驻挂载 + 位移切换：容器位移用 GeometryReader 实测高度（弃
///    UIScreen.main.bounds），spring 动画结束后同步 webView.isHidden，
///    离屏不进合成。展开/收起状态唯一来源是 RenderStateCenter。
/// 2. 引擎尚无曲目（加载中 / 点播失败）时的原生兜底信息层，杜绝无歌名
///    无提示的纯黑播放页（3.3 录屏实证）。
/// 3. 网页未加载成功或进程自愈停摆时，左上留一个原生收起钮（与网页自带
///    返回钮同位），防用户被困在播放页出不去。
/// WebEffect WebView 本体由 WebEffectBridge 单例持有，容器只包装，不重建。
struct FullPlayerContainer: View {
    @ObservedObject var engine = PlaybackEngine.shared
    @ObservedObject var bridge = WebEffectBridge.shared
    @ObservedObject var renderCenter = RenderStateCenter.shared
    @ObservedObject var queueManager = QueueManager.shared
    var onDismiss: () -> Void

    private var isOpen: Bool { renderCenter.isFullPlayerOpen }

    /// 网页不可用（未加载完 / 自愈停摆）：播放页自带 UI 指望不上，
    /// 原生收起钮是唯一的出路。
    private var webUnavailable: Bool {
        !bridge.isPageLoaded || bridge.lastFatalError != nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底层深色底板，防止网页加载瞬间透出底层主页。
                Color.black.ignoresSafeArea()

                // 核心：Folia 网页特效面 + 它自带的播放页 UI（桥单例持有，
                // 常驻不重建）。
                WebEffectView(webView: bridge.webView)
                    .ignoresSafeArea()

                // 引擎尚无曲目但队列里有选中曲（加载中 / 点播失败）：原生兜底
                // 信息层，杜绝无歌名无提示的纯黑播放页（3.3 录屏实证）。
                if engine.currentTrack == nil, let selected = queueManager.currentTrack {
                    VStack(spacing: 14) {
                        NativeCoverView(url: selected.artworkURL, targetPixels: 500)
                            .frame(width: 180, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(spacing: 4) {
                            Text(selected.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(selected.artist)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        if let error = queueManager.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .padding(.bottom, 40)
                }

                // 有曲目在播但最近一次点播/切歌失败：顶部错误小药丸。这不是
                // 控制条，只是把 QueueManager 的报错露出来（网页没有报错面），
                // 下一首成功起播后 lastError 清空、药丸自动消失。
                if engine.currentTrack != nil, let error = queueManager.lastError {
                    VStack {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.55))
                            .clipShape(Capsule())
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .padding(.top, 64)
                }

                // 网页不可用时的原生收起钮（左上，与网页自带返回钮同位同尺寸）。
                if webUnavailable {
                    VStack {
                        HStack {
                            Button(action: onDismiss) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("收起播放页")
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.top, 24)
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
}
