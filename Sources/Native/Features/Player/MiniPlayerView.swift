import SwiftUI

/// 原生悬浮迷你播放条（M2，native-arch.md §10）：全 App 唯一播放条。
///
/// 悬浮卡片＋顶部细进度条＋封面 / 歌名歌手 / 播放暂停 / 下一首。
/// 只订阅 PlaybackEngine 的 @Published 状态（不另起 onTimeSync 单回调；
/// 多播由 M1 在引擎侧处理，本视图只做 Published 订阅兜底）。
/// 无曲目时不渲染内容；可见性由 MainViewController 按 currentTrack 控制。
struct MiniPlayerView: View {
    @ObservedObject var engine = PlaybackEngine.shared
    var onTapExpand: () -> Void

    private var progress: Double {
        guard engine.duration > 0, engine.duration.isFinite else { return 0 }
        return min(max(engine.currentTime / engine.duration, 0), 1)
    }

    var body: some View {
        if let track = engine.currentTrack {
            VStack(spacing: 0) {
                // 顶部细进度条（2pt）。
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.primary.opacity(0.08)
                        Color.accentColor
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 12) {
                    MiniCoverView(artworkURL: track.artworkURL)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if track.sourceType == .local {
                                Text("本地")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(track.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")

                    Button {
                        QueueManager.shared.playNext(manual: true)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下一首")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onTapExpand()
            }
        }
    }
}

/// 迷你条封面：远程 URL 走 AsyncImage；本地 file URL 走 UIImage 加载
///（不直接用 AsyncImage 加载 file URL，见 native-arch.md §7 M3 登记 ⑦）。
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
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "music.note")
                .foregroundColor(.secondary)
        }
    }
}
