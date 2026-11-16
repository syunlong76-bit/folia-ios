import SwiftUI

/// 原生浏览面根（3.3 起全原生；主页/集合页 2026-11-16 按 Folia 源码逐页移植）。
/// 结构：NavigationStack（探索页为根，集合页经 ExploreCollection 路由压栈）+
/// 搜索页。点歌直进 QueueManager 原生队列；迷你条是全 App 唯一播放条。
/// 视觉口径 = Folia 默认主题 Midnight Default（baseThemes）。
struct NativeBrowseView: View {
    @ObservedObject private var engine = PlaybackEngine.shared
    /// 导航路径提到根上：探索页的搜索覆盖层点开集合时，收起后经路径压栈。
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ExploreView(path: $path)
                .navigationDestination(for: ExploreCollection.self) { collection in
                    CollectionView(collection: collection)
                }
        }
        .preferredColorScheme(.dark)
        // 底部给原生迷你条让位（迷你条是壳层浮层，不在 SwiftUI 布局内）。
        .safeAreaInset(edge: .bottom) {
            if engine.currentTrack != nil {
                Color.clear.frame(height: 80)
            }
        }
    }

    static func openFullPlayer() {
        RenderStateCenter.shared.setFullPlayerOpen(true)
    }
}

/// Folia 默认主题色板（Midnight Default，folia-major/src/services/baseThemes.ts）。
enum FoliaTheme {
    static let background = Color(red: 0x09 / 255, green: 0x09 / 255, blue: 0x0B / 255)
    static let primary = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255)
    static let secondary = Color(red: 0x71 / 255, green: 0x71 / 255, blue: 0x7A / 255)
    static let card = Color.white.opacity(0.06)
    static let field = Color.white.opacity(0.09)
}

// MARK: - 搜索

// 3.3 的自创搜索页已于 2026-11-16 逐页移植时撤除：搜索统一走
// SearchWorkspaceView（Folia 搜索工作区规格），从探索页顶部入口行以
// 全屏覆盖层打开（见 ExploreView.searchEntry）。

func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
}
