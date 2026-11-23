import ActivityKit
import SwiftUI
import WidgetKit

/// (75) FoliaWidgets 扩展入口：v1 只承载灵动岛宠物 Live
/// Activity 一个 Widget。呈现全部由系统排版（紧凑/展开/
/// 最小/锁屏四形态与时间、信号共存是系统设计内行为，与
/// 应用内障眼法落法形成两条路——见交付报告）。
@main
struct FoliaWidgets: WidgetBundle {
    var body: some Widget {
        FoliaIslandActivityWidget()
    }
}

private struct FoliaIslandActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FoliaIslandAttributes.self) { context in
            // 锁屏横幅（DS 对账次要 D：独立成版，不依赖岛形态）。
            FoliaIslandLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开形态：左右放大宠物 + 中央歌名/歌手/一句词。
                DynamicIslandExpandedRegion(.leading) {
                    FoliaPetImage(id: context.state.leftPetId, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FoliaPetImage(id: context.state.rightPetId, size: 44)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    // (77) ⑩：中央只留歌曲信息（歌名/歌手），
                    // 台词移到底部独立行——不许挤掉歌曲信息。
                    VStack(spacing: 2) {
                        Text(context.state.songTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        // (77) ⑩台词独立行：按说话侧对齐呈现
                        // 归属（左住客说的话靠左、右住客靠
                        // 右），一眼看出是谁在说。
                        if !context.state.phrase.isEmpty {
                            HStack(spacing: 4) {
                                if context.state.phraseSide == 1 {
                                    Spacer()
                                }
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Text(context.state.phrase)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if context.state.phraseSide == 0 {
                                    Spacer()
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: context.state.isPlaying
                                  ? "play.fill" : "pause.fill")
                                .font(.caption2)
                            Text(context.state.isPlaying ? "播放中" : "已暂停")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // 紧凑形态：左猫右狗整只可见（首帧静态图、
                // scaledToFit 小框，DS 对账重要 D）。
                FoliaPetImage(id: context.state.leftPetId, size: 22)
            } compactTrailing: {
                FoliaPetImage(id: context.state.rightPetId, size: 22)
            } minimal: {
                FoliaPetImage(id: context.state.leftPetId, size: 22)
            }
            .keylineTint(.orange)
        }
    }
}

/// 宠物图（扩展包内 imageset、id = 资产名）。图缺失时以爪
/// 印符号兜底，不许空白（53 只已全量打包，此为防御）。
private struct FoliaPetImage: View {
    let id: String
    let size: CGFloat

    var body: some View {
        if UIImage(named: id) != nil {
            Image(id)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
        }
    }
}

/// 锁屏横幅：双宠物 + 歌名/歌手 + 一句词 + 播放态，独立
/// 于岛形态可用。
private struct FoliaIslandLockScreenView: View {
    let state: FoliaIslandAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                FoliaPetImage(id: state.leftPetId, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.songTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: state.isPlaying ? "play.fill" : "pause.fill")
                    .font(.body)
                FoliaPetImage(id: state.rightPetId, size: 40)
            }
            // (77) ⑩台词独立行（锁屏面同岛口径）：按说话
            // 侧对齐——左住客的话靠左、右住客的话靠右，
            // 歌曲信息行不被挤占。
            if !state.phrase.isEmpty {
                HStack(spacing: 4) {
                    if state.phraseSide == 1 { Spacer() }
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(state.phrase)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if state.phraseSide == 0 { Spacer() }
                }
            }
        }
        .padding(12)
        .activityBackgroundTint(Color.black.opacity(0.55))
        .activitySystemActionForegroundColor(.white)
    }
}
