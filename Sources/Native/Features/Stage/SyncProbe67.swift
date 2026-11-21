import AVFoundation
import Foundation

/// §0 同步量测探针（3.7 (67) B 组，纯日志）：引擎侧出声基准
/// 与呈现侧提交/收敛时刻统一落面包屑，供真机一轮判读「歌词
/// 慢」在哪一段。红线：本文件只记数，不改任何 lead/偏移。
/// 字段口径见 forensics/effect-feedback-2026-11-21-plan.md §0：
/// judge=呈现钟（锚外推）、raw=rawPlayhead 真值、sndEst=raw
/// 扣 outputLatency 的出声估计、wordSrc 按行词戳覆盖分组。
enum SyncProbe67 {

    /// 音频会话三读数（route 名/outLat/ioBuf，秒）。
    static func audioFields() -> (route: String, outLat: Double, ioBuf: Double) {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
        return (route, session.outputLatency, session.ioBufferDuration)
    }

    /// 当前行表的词戳覆盖分组（与 LyricRepository 判读同口径）。
    static func wordSource(of lines: [LyricLine]) -> String {
        guard !lines.isEmpty else { return "none" }
        let withWords = lines.filter { $0.words != nil }.count
        if withWords == 0 { return "uniform" }
        return withWords == lines.count ? "yrc" : "mixed"
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
