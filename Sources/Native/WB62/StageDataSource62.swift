import Foundation

/// (62) WB §4.9：舞台模式 + 舞台数据来源（外部舞台数据源）。
///
/// 协议假设（如实标注）：数据源 URL 返回 JSON
/// `{ "title": String, "artist": String, "progress": Double }`
/// （progress 为 0...1 播放进度；字段缺失按空/0 兜底）。客户
/// 端每 5 秒轮询一次，把结果经通知 .foliaExternalStageData
/// 映射给舞台信息卡数据源（WA 在 StageVC 订阅后回填信息
/// 卡）；默认关（stageModeEnabled=false 或 URL 空时不启
/// 动），无源时舞台行为与现行完全一致。启动点：设置行开关
/// 拨动时即时启停 + PlaybackEngine init 时 startIfEnabled
/// 兜底冷启恢复。
final class StageDataSource62 {

    static let shared = StageDataSource62()

    private var timer: Timer?
    private var inFlight = false

    private init() {}

    func startIfEnabled() {
        guard SettingsStore.stageModeEnabled,
              !SettingsStore.stageDataSourceURL
                .trimmingCharacters(in: .whitespaces).isEmpty else {
            stop()
            return
        }
        guard timer == nil else { return }
        Breadcrumbs.log("stage62.datasource start url=\(SettingsStore.stageDataSourceURL)")
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func restart() {
        stop()
        startIfEnabled()
    }

    private func poll() {
        guard !inFlight,
              let url = URL(string: SettingsStore.stageDataSourceURL
                .trimmingCharacters(in: .whitespaces)) else { return }
        inFlight = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            defer { self?.inFlight = false }
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let title = json["title"] as? String ?? ""
            let artist = json["artist"] as? String ?? ""
            let progress = (json["progress"] as? NSNumber)?.doubleValue ?? 0
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .foliaExternalStageData, object: nil,
                    userInfo: ["title": title, "artist": artist,
                               "progress": min(max(progress, 0), 1)])
            }
        }.resume()
    }
}
