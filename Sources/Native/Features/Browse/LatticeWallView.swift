import SwiftUI

/// Lattice 格子墙（队列海报墙）原生移植（移植规格 port-spec-lattice-collection.md 第一节）。
///
/// 形态照 folia-major 源码（Lattice.tsx / PosterWall / wall.css / LatticeChrome.css）：
/// 当前播放队列整队铺成方形海报墙（直角无圆角、间距 8），点海报先展开再播放。
/// 桌面版是可拖动平移的无限平铺墙；移动端以纵向滚动网格等价实现（见交付报告）。
/// 数据 = QueueManager 当前队列 + 当前歌曲；封面走 NativeCoverView 既有加载链。
/// 导航不归本视图管：关闭走 onClose、打开播放器走 onOpenPlayer（协调者接线）。
struct LatticeWallView: View {
    /// 左上返回：展开态先收起展开（由本视图内部处理），未展开时回调协调者关闭墙。
    var onClose: () -> Void = {}
    /// 展开态「打开播放器」：协调者负责关墙 + 开播放页。
    var onOpenPlayer: () -> Void = {}

    @ObservedObject private var queueManager = QueueManager.shared
    @ObservedObject private var engine = PlaybackEngine.shared

    /// 当前展开的海报下标（队列下标）；nil = 未展开。
    @State private var expandedIndex: Int?
    /// 展开条进度拖动中的临时进度（秒）；nil = 未拖动，跟随引擎。
    @State private var scrubTime: Double?

    // Midnight Default 令牌（与 NativeBrowseView 的 FoliaTheme 同源）。
    private var ink: Color { FoliaTheme.primary }
    private var accent: Color { FoliaTheme.primary } // Midnight 下强调色 == 主色 #f4f4f5

    var body: some View {
        ZStack(alignment: .topLeading) {
            FoliaTheme.background.ignoresSafeArea()

            if queueManager.queue.isEmpty {
                emptyState
            } else {
                wallGrid
            }

            // 展开层（盖在墙上，返回钮在其上层）。
            if let index = expandedIndex,
               queueManager.queue.indices.contains(index) {
                expandedPoster(index: index, track: queueManager.queue[index])
                    .transition(.opacity)
                    .zIndex(2)
            }

            backButton
                .zIndex(3)
        }
        .preferredColorScheme(.dark)
        .onChange(of: queueManager.queue.count) { _, _ in
            // 队列变化后展开下标可能越界：越界即收起。
            if let index = expandedIndex, !queueManager.queue.indices.contains(index) {
                expandedIndex = nil
            }
        }
    }

    // MARK: - 返回钮（WallBackButton：40×40 圆、白 8% 底 + blur、top 20 / left 24）

    private var backButton: some View {
        Button {
            if expandedIndex != nil {
                withAnimation(.easeOut(duration: 0.2)) { expandedIndex = nil }
            } else {
                onClose()
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(ink)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.24), radius: 15, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
        .padding(.leading, 24)
    }

    // MARK: - 空态（wall.css：两行居中文案）

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("队列是空的")
                .font(.system(size: 17))
                .tracking(17 * 0.16)
                .foregroundColor(ink)
            Text("开始播放任意歌曲后，队列会在这里铺开。")
                .font(.system(size: 12))
                .foregroundColor(ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 海报墙（滚动网格）

    private var wallGrid: some View {
        GeometryReader { geo in
            // 边长约 128pt 量级：按可用宽度取整列数，格子均分整宽。
            let columns = max(2, Int(((geo.size.width + 8) / 136).rounded()))
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                    spacing: 8
                ) {
                    ForEach(Array(queueManager.queue.enumerated()), id: \.offset) { index, track in
                        posterTile(index: index, track: track)
                    }
                }
            }
        }
    }

    /// 单张海报：封面全幅 → 底部渐变罩 → 左上序号牌 → 底部文案，全直角。
    private func posterTile(index: Int, track: FoliaTrack) -> some View {
        // 按下标判定正在播：同曲在队列中重复出现时不双亮（id 判定会误亮）。
        let isCurrent = index == queueManager.currentIndex
        return ZStack(alignment: .topLeading) {
            NativeCoverView(url: track.artworkURL, targetPixels: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部渐变罩（wall.css .lattice-poster-shade：5%@34% → 24%@56% → 92%@100%）。
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0.34),
                    .init(color: .black.opacity(0.24), location: 0.56),
                    .init(color: .black.opacity(0.92), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )

            // 正在播：2px 强调色内描边（.lattice-poster.is-current::before）。
            if isCurrent {
                Rectangle()
                    .stroke(accent, lineWidth: 2)
            }

            // 序号牌（top/left 14、padding 5/8、11px 800、tabular-nums、字距 0.12em）。
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .heavy).monospacedDigit())
                .tracking(11 * 0.12)
                .foregroundColor(isCurrent ? accent : ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(isCurrent ? 0.78 : 0.62))
                .padding(.top, 14)
                .padding(.leading, 14)

            // 底部文案（距边 17、gap 5）。
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-22 * 0.045)
                    .lineSpacing(-2) // 行高 0.96 的近似（SwiftUI 无 em 行高）
                    .lineLimit(3)
                    .foregroundColor(ink)
                Text(track.artist)
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.78)
                    .lineLimit(1)
                    .foregroundColor(ink)
            }
            .padding(17)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.22)) { expandedIndex = index }
        }
    }

    // MARK: - 展开态（全屏单张海报 + 底部播放条）

    private func expandedPoster(index: Int, track: FoliaTrack) -> some View {
        let isCurrent = index == queueManager.currentIndex
        return GeometryReader { geo in
            // 展开歌名：≤640px 宽时 44px（wall.css 移动端断点），否则 clamp(48, 6vw, 82)。
            let titleSize: CGFloat = geo.size.width <= 640
                ? 44
                : min(82, max(48, geo.size.width * 0.06))
            ZStack(alignment: .bottomLeading) {
                NativeCoverView(url: track.artworkURL, targetPixels: 1000)
                    .frame(width: geo.size.width, height: geo.size.height)

                // 展开罩：底部带（86%@0 → 62%@14% → 26%@30% → 0%@46%）+ 左侧带。
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.86), location: 0),
                        .init(color: .black.opacity(0.62), location: 0.14),
                        .init(color: .black.opacity(0.26), location: 0.30),
                        .init(color: .black.opacity(0), location: 0.46)
                    ],
                    startPoint: .bottom, endPoint: .top
                )
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.88), location: 0),
                        .init(color: .black.opacity(0.50), location: 0.52),
                        .init(color: .black.opacity(0.08), location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )

                // 收起热区：海报上半部点按收起（下半部是文案与播放条，不抢手势）。
                VStack {
                    Color.clear
                        .frame(height: geo.size.height * 0.45)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { expandedIndex = nil }
                        }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 18) {
                    // 文案（left/right 32、歌名最大宽 76%、歌手 17px）。
                    VStack(alignment: .leading, spacing: 7) {
                        Text(track.title)
                            .font(.system(size: titleSize, weight: .bold))
                            .tracking(-titleSize * 0.045)
                            .lineLimit(3)
                            .foregroundColor(ink)
                            .frame(maxWidth: geo.size.width * 0.76, alignment: .leading)
                        Text(track.artist)
                            .font(.system(size: 17, weight: .semibold))
                            .opacity(0.78)
                            .lineLimit(1)
                            .foregroundColor(ink)
                    }

                    chrome(index: index, track: track, isCurrent: isCurrent)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    /// 展开后播放条（LatticeChrome.css）：主按钮 → 上一首/下一首 → 时间 → 打开播放器，
    /// 下方整宽直角进度条。按钮 44×44、图标 20px；次级按钮 opacity 0.65；时间 mono 12 opacity 0.6。
    private func chrome(index: Int, track: FoliaTrack, isCurrent: Bool) -> some View {
        let duration = isCurrent && engine.duration > 0 ? engine.duration : track.duration
        let displayTime = scrubTime ?? (isCurrent ? engine.currentTime : 0)
        let fraction = duration > 0 ? min(1, max(0, displayTime / duration)) : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 主按钮：当前歌 = 切暂停；非当前歌 = 播这张牌（队列保持现有队列）。
                Button {
                    if isCurrent {
                        engine.togglePlayPause()
                    } else {
                        queueManager.playAtIndex(index)
                    }
                } label: {
                    Image(systemName: isCurrent && engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                // 上一首 / 下一首（可配槽位未移植，见报告）。
                Button {
                    queueManager.playPrevious()
                    expandedIndex = queueManager.currentIndex
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(0.65)
                .disabled(queueManager.queue.count < 2)

                Button {
                    queueManager.playNext(manual: true)
                    expandedIndex = queueManager.currentIndex
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 20))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(0.65)
                .disabled(queueManager.queue.count < 2)

                Spacer(minLength: 8)

                // 时间（当前 / 时长）。
                Text("\(latticeFormatTime(displayTime)) / \(latticeFormatTime(duration))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(ink)
                    .opacity(0.6)

                // 打开播放器。
                Button { onOpenPlayer() } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 20))
                        .foregroundColor(ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .opacity(0.65)
            }

            // 进度条：2px 直角线、36px 高命中区；仅展开牌是当前歌时可拖 seek。
            LatticeProgressBar(
                fraction: fraction,
                enabled: isCurrent,
                ink: ink
            ) { newFraction in
                scrubTime = newFraction * duration
            } onCommit: { newFraction in
                engine.seek(to: newFraction * duration)
                scrubTime = nil
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
        .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
    }
}

/// Lattice 展开条的直角进度条（LatticeChrome.css .lattice-progress：线高 2px、命中区 36px）。
private struct LatticeProgressBar: View {
    let fraction: Double
    let enabled: Bool
    let ink: Color
    var onScrub: (Double) -> Void
    var onCommit: (Double) -> Void

    @State private var dragFraction: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ink.opacity(0.25))
                    .frame(height: 2)
                Rectangle()
                    .fill(ink)
                    .frame(width: geo.size.width * CGFloat(dragFraction ?? fraction), height: 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        let f = min(1, max(0, value.location.x / geo.size.width))
                        dragFraction = f
                        onScrub(f)
                    }
                    .onEnded { value in
                        guard enabled else { return }
                        let f = min(1, max(0, value.location.x / geo.size.width))
                        dragFraction = nil
                        onCommit(f)
                    }
            )
        }
        .frame(height: 36)
        .opacity(enabled ? 1 : 0.55)
    }
}

/// mm:ss（LatticeChromeTime 同口径）。
private func latticeFormatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
