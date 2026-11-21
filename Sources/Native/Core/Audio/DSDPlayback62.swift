import AVFoundation
import Foundation

/// (66) DSD 播放通路（DS 改判「有条件」落地）：本地 .dsf
/// 文件经 PlaybackEngine.load 的钩子进入本组件——
/// - 开关 dsdDopEnabled62 开且能力检测通过（外接输出＋会
///   话采样率 ≥176.4kHz）时，把 DSD64 码流按 DoP 规范封
///   装进 176.4kHz/24bit WAV（每帧高字节交替 0x05/0xFA
///   标记＋16 bit DSD 载荷），由支持 DoP 的外接 DAC 还原；
/// - 条件不满足时明示降级：解码为普通 PCM WAV（盒式均值
///   抽取，音质为近似）播放，面包屑写清走的哪条路，不静
///   默假装 DoP；
/// - 解析失败返回 nil，引擎回原路径（转码/跳过逻辑）。
///
/// 诚实边界：iOS 的 AVPlayer 链路会把音频经系统混音与重
/// 采样，DoP 的 bit-perfect 只在系统以 176.4kHz 直通外接
/// 输出时成立——本组件保证「封装正确＋条件明示」，实际听
/// 感取决于外接设备与系统路由，设置行文案同口径。
enum DSDPlayback62 {

    // MARK: - 能力检测

    /// 当前输出条件摘要（设置行与日志共用）。
    static var capabilitySummary: String {
        let session = AVAudioSession.sharedInstance()
        let port = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
        return "route=\(port) rate=\(Int(session.sampleRate))Hz"
    }

    /// DoP 条件：存在外接输出（非内置扬声器/听筒）且会话
    /// 采样率达到 DoP 载波 176.4kHz。
    static var dopCapable: Bool {
        let session = AVAudioSession.sharedInstance()
        let hasExternal = session.currentRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
        return hasExternal && session.sampleRate >= 176_400
    }

    // MARK: - DSF 解析

    struct DSFInfo {
        var channels: Int
        var sampleRate: Int      // DSD 采样率（2822400 = DSD64）
        var sampleCount: UInt64  // 每声道样本数（bit 数）
        var blockSize: Int       // 每声道块字节（通常 4096）
        var dataOffset: Int      // data 载荷起始
        var dataBytes: Int
    }

    static func parseDSF(_ data: Data) -> DSFInfo? {
        func u32(_ offset: Int) -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
        }
        func u64(_ offset: Int) -> UInt64? {
            guard offset + 8 <= data.count else { return nil }
            return data.withUnsafeBytes { raw in
                UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            }
        }
        guard data.count > 28,
              String(bytes: data[0..<4], encoding: .ascii) == "DSD ",
              let fmtOffset = u64(20).map({ Int($0) }), fmtOffset > 0,
              fmtOffset + 52 <= data.count,
              String(bytes: data[fmtOffset..<(fmtOffset + 4)], encoding: .ascii) == "fmt ",
              // fmt 块布局（DSF 规范）：+12 版本 / +16 格式 /
              // +20 声道类型 / +24 声道数 / +28 采样率 /
              // +32 每样本位 / +36 样本数(u64) / +44 块大小。
              let channels = u32(fmtOffset + 24).map({ Int($0) }),
              channels == 1 || channels == 2,
              let sampleRate = u32(fmtOffset + 28).map({ Int($0) }),
              sampleRate == 2_822_400 || sampleRate == 5_644_800,
              let sampleCount = u64(fmtOffset + 36),
              let blockSize = u32(fmtOffset + 44).map({ Int($0) }), blockSize > 0
        else { return nil }
        // data chunk 在 fmt 之后（fmt chunk 大小在 fmt+4 的 u64）。
        guard let fmtSize = u64(fmtOffset + 4) else { return nil }
        let dataChunk = fmtOffset + Int(fmtSize)
        guard dataChunk + 12 <= data.count,
              String(bytes: data[dataChunk..<(dataChunk + 4)], encoding: .ascii) == "data",
              let dataSize = u64(dataChunk + 4) else { return nil }
        let payload = dataChunk + 12
        return DSFInfo(channels: channels, sampleRate: sampleRate,
                       sampleCount: sampleCount, blockSize: blockSize,
                       dataOffset: payload,
                       dataBytes: min(Int(dataSize) - 12, data.count - payload))
    }

    /// 按声道拆出 DSD 字节流（DSF 为块交织：块序为
    /// [ch0 块][ch1 块]…；每字节内样本位序按 DSF 规范
    /// LSB-first，取出时翻转为 MSB-first 的时间序）。
    private static func channelBits(_ data: Data, info: DSFInfo, channel: Int) -> [UInt8] {
        let blockCount = info.dataBytes / (info.blockSize * info.channels)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(blockCount * info.blockSize)
        for block in 0..<blockCount {
            let start = info.dataOffset + (block * info.channels + channel) * info.blockSize
            guard start + info.blockSize <= data.count else { break }
            for i in 0..<info.blockSize {
                bytes.append(data[start + i].reversedBits)
            }
        }
        return bytes
    }

    // MARK: - 转换（产物落 Caches/folia-dsd，按源文件指纹复用）

    /// 返回 (产物 URL, 是否 DoP 封装)。失败 nil。
    static func convertDSF(_ source: URL) -> (URL, Bool)? {
        let key = "\(source.path)-\((try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue ?? 0)"
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("folia-dsd", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = "dsf-\(abs(key.hashValue))"
        guard let data = try? Data(contentsOf: source, options: .mappedIfSafe),
              let info = parseDSF(data) else {
            Breadcrumbs.log("dsd66 parse failed file=\(source.lastPathComponent)")
            return nil
        }
        let useDoP = SettingsStore.dsdDopEnabled62 && dopCapable && info.sampleRate == 2_822_400
        let out = dir.appendingPathComponent(stem + (useDoP ? "-dop.wav" : "-pcm.wav"))
        if FileManager.default.fileExists(atPath: out.path) {
            Breadcrumbs.log("dsd66 reuse cached dop=\(useDoP ? 1 : 0)")
            return (out, useDoP)
        }
        let ch0 = channelBits(data, info: info, channel: 0)
        let ch1 = info.channels > 1 ? channelBits(data, info: info, channel: 1) : ch0
        let ok = useDoP
            ? writeDoPWAV(to: out, ch0: ch0, ch1: ch1)
            : writePCMWAV(to: out, ch0: ch0, ch1: ch1)
        guard ok else {
            Breadcrumbs.log("dsd66 convert failed dop=\(useDoP ? 1 : 0)")
            return nil
        }
        Breadcrumbs.log("dsd66 converted dop=\(useDoP ? 1 : 0) "
            + "capable=\(dopCapable ? 1 : 0) \(capabilitySummary)")
        return (out, useDoP)
    }

    /// DoP 封装：176.4kHz / 24bit 立体声 WAV；每帧载荷 =
    /// 16 个 DSD bit（MSB-first），高字节标记 0x05/0xFA 按
    /// 帧交替（左右声道同帧同标记，DoP 规范）。
    private static func writeDoPWAV(to url: URL, ch0: [UInt8], ch1: [UInt8]) -> Bool {
        let framesPerChannel = min(ch0.count, ch1.count) * 8 / 16
        var pcm = Data()
        pcm.reserveCapacity(framesPerChannel * 2 * 3)
        for frame in 0..<framesPerChannel {
            let marker: UInt8 = frame % 2 == 0 ? 0x05 : 0xFA
            for channel in [ch0, ch1] {
                let bitBase = frame * 16
                var payload: UInt16 = 0
                for b in 0..<16 {
                    let byte = channel[(bitBase + b) / 8]
                    let bit = (byte >> (7 - (bitBase + b) % 8)) & 1
                    payload = (payload << 1) | UInt16(bit)
                }
                pcm.append(UInt8(payload & 0xFF))
                pcm.append(UInt8(payload >> 8))
                pcm.append(marker)
            }
        }
        return writeWAV(to: url, pcm: pcm, channels: 2, sampleRate: 176_400, bitsPerSample: 24)
    }

    /// PCM 降级：每 16 个 DSD bit 盒式均值 → 一个 176.4kHz
    /// 16bit 样本（幅度 = 置位比 ×2−1）。近似解码，只求可
    /// 播与可辨，不冒充高保真。
    private static func writePCMWAV(to url: URL, ch0: [UInt8], ch1: [UInt8]) -> Bool {
        let framesPerChannel = min(ch0.count, ch1.count) * 8 / 16
        var pcm = Data()
        pcm.reserveCapacity(framesPerChannel * 2 * 2)
        for frame in 0..<framesPerChannel {
            for channel in [ch0, ch1] {
                var ones = 0
                for b in 0..<16 {
                    let byte = channel[(frame * 16 + b) / 8]
                    ones += Int((byte >> (7 - (frame * 16 + b) % 8)) & 1)
                }
                let amplitude = (Double(ones) / 16 * 2 - 1) * 0.9
                var sample = Int16(amplitude * Double(Int16.max)).littleEndian
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }
        }
        return writeWAV(to: url, pcm: pcm, channels: 2, sampleRate: 176_400, bitsPerSample: 16)
    }

    private static func writeWAV(to url: URL, pcm: Data, channels: Int,
                                 sampleRate: Int, bitsPerSample: Int) -> Bool {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var header = Data()
        func tag(_ text: String) { header.append(contentsOf: text.utf8) }
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        tag("RIFF"); u32(UInt32(36 + pcm.count)); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(UInt16(channels))
        u32(UInt32(sampleRate)); u32(UInt32(byteRate)); u16(UInt16(blockAlign)); u16(UInt16(bitsPerSample))
        tag("data"); u32(UInt32(pcm.count))
        var file = header
        file.append(pcm)
        do { try file.write(to: url, options: .atomic); return true } catch { return false }
    }
}

private extension UInt8 {
    /// 字节内位序翻转（DSF 的 LSB-first → 时间序 MSB-first）。
    var reversedBits: UInt8 {
        var v = self
        v = (v & 0x55) << 1 | (v & 0xAA) >> 1
        v = (v & 0x33) << 2 | (v & 0xCC) >> 2
        v = v << 4 | v >> 4
        return v
    }
}
