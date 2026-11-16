import SwiftUI

/// 原生悬浮迷你播放条（M2；2026-11-16 按 Folia 自带 BrowseMiniBar 对齐数值）。
///
/// 规格（folia-major/src/components/app/shellBridge/BrowseMiniBar.tsx）：
/// inset-x 12、bottom = 12 + 安全区（宿主在 MainViewController 侧对齐）、
/// rounded-2xl、border white/10、bg zinc-900/85、backdrop-blur、px-3 py-2、
/// gap-3；封面 40×40 rounded-lg（无封面为 white/10 空块）；歌名 14 medium
/// 白色 + 歌手 12 white/60；上一首 20 / 播放暂停 24 / 下一首 20（走带键
/// white/80、播放键 white，p-2）；点条身开播放页；无当前歌曲不渲染。
/// 宿主可见性仍由 MainViewController 按 currentTrack 控制。
struct MiniPlayerView: View {
    @ObservedObject var engine = PlaybackEngine.shared
    var onTapExpand: () -> Void

    var body: some View {
        if let track = engine.currentTrack {
            HStack(spacing: 12) {
                MiniCoverView(artworkURL: track.artworkURL)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    QueueManager.shared.playPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上一首")

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")

                Button {
                    QueueManager.shared.playNext(manual: true)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
            .contentShape(Rectangle())
            .onTapGesture {
                onTapExpand()
            }
        }
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
