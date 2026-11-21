import Foundation
import UIKit

// LyricExport62.swift
//
// 3.7 (62) WC 簇 §8/§4.10 歌词导出本体：
// - .lrc：由 LyricRepository 合并行表生成标准 LRC 文本。
// - .fia：JSON（folia lyric archive）——含逐行时刻与逐字戳
//   （LyricLine.words），供外部工具/再导入使用。
// 入口三处真达：设置行（存储与备份）、命令面板「歌词」组、
// 播放面板歌词页签长按。导出走系统分享/存文件
// （UIActivityViewController）。

enum LyricExport62 {

    struct ExportFile {
        let url: URL
        let format: String
    }

    private static func safeFileName(_ text: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        return text.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func lrcTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        let minutes = Int(total) / 60
        let secs = total - Double(minutes * 60)
        return String(format: "[%02d:%05.2f]", minutes, secs)
    }

    /// 为指定曲目生成导出文件（临时目录）。无歌词返回 nil。
    static func makeFiles(for track: FoliaTrack) async -> [ExportFile] {
        let entry = await LyricRepository.shared.entry(for: track.id)
        guard !entry.lines.isEmpty else {
            Breadcrumbs.log("lyricExport62.empty id=\(track.id)")
            return []
        }
        let stageLines = LyricParser.stageLines(
            from: entry.lines, trackDuration: track.duration,
            singingRatio: entry.singingRatio)
        let base = safeFileName("\(track.title) - \(track.artist)")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folia-lyric-export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var files: [ExportFile] = []
        // .lrc
        var lrc = "[ti:\(track.title)]\n[ar:\(track.artist)]\n"
        if !track.album.isEmpty { lrc += "[al:\(track.album)]\n" }
        for line in stageLines where !line.text.isEmpty {
            lrc += "\(lrcTimestamp(line.start))\(line.text)\n"
        }
        let lrcURL = dir.appendingPathComponent(base + ".lrc")
        if (try? lrc.write(to: lrcURL, atomically: true, encoding: .utf8)) != nil {
            files.append(ExportFile(url: lrcURL, format: "lrc"))
        }
        // .fia（JSON：逐行＋逐字戳）
        let fiaLines: [[String: Any]] = stageLines.map { line in
            var dict: [String: Any] = [
                "start": line.start, "end": line.end, "text": line.text,
            ]
            if let words = line.words {
                dict["words"] = words.map {
                    ["start": $0.start, "end": $0.end, "text": $0.text]
                }
            }
            return dict
        }
        let fia: [String: Any] = [
            "format": "folia-lyric-archive",
            "version": 1,
            "track": ["id": track.id, "title": track.title,
                      "artist": track.artist, "album": track.album,
                      "duration": track.duration],
            "source": entry.source,
            "lines": fiaLines,
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: fia, options: [.prettyPrinted, .sortedKeys]) {
            let fiaURL = dir.appendingPathComponent(base + ".fia")
            if (try? data.write(to: fiaURL, options: .atomic)) != nil {
                files.append(ExportFile(url: fiaURL, format: "fia"))
            }
        }
        Breadcrumbs.log("lyricExport62.made id=\(track.id) files=\(files.count)")
        return files
    }

    /// 导出当前播放曲目并弹系统分享。无曲目/无歌词时 toast 诚实回显。
    static func exportCurrentTrack(from presenter: UIViewController) {
        guard let track = PlaybackEngine.shared.currentTrack else {
            NativePlaybackFailureToast.show(message: "暂无正在播放的歌曲")
            return
        }
        Task { @MainActor in
            let files = await makeFiles(for: track)
            guard !files.isEmpty else {
                NativePlaybackFailureToast.show(message: "当前歌曲暂无歌词可导出")
                return
            }
            presentShare(files: files, from: presenter)
        }
    }

    static func export(track: FoliaTrack, from presenter: UIViewController) {
        Task { @MainActor in
            let files = await makeFiles(for: track)
            guard !files.isEmpty else {
                NativePlaybackFailureToast.show(message: "该歌曲暂无歌词可导出")
                return
            }
            presentShare(files: files, from: presenter)
        }
    }

    @MainActor
    static func presentShare(files: [ExportFile], from presenter: UIViewController) {
        let activity = UIActivityViewController(
            activityItems: files.map { $0.url }, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 1, height: 1)
        }
        presenter.present(activity, animated: true)
    }
}
