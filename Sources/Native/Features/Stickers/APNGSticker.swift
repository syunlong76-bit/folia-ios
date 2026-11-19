import UIKit
import ImageIO

// 贴纸基础设施（3.7 (24)，纯新增）：APNG 解码 + 帧播放视图。
//
// 资产口径（scene-mapping.md 终版）：素材包 APNG 全部为
// dispose=NONE / blend=SOURCE（convert.py 产物，verify-report
// 全量校验通过）；解码器仍按 APNG 规范实现三种 dispose 与
// 两种 blend，逐帧合成全画布帧后播放——只播素材本体帧，
// 不改帧、不补帧、不自编动作。
//
// 狗贴纸为白底素材：映射口径「出场位置须是白色/浅色底面」。
// 深色宿主（舞台/墙/设置卡）上以浅色圆角贴纸底（tile）承载，
// StickerView.showsTileBackground 即此落实；猫为透明底不用。

/// 解码结果（类包装，供 NSCache 持有）。
final class APNGDecoded {
    let frames: [CGImage]
    let durations: [TimeInterval]
    let totalDuration: TimeInterval
    let canvasSize: CGSize
    var memoryCost: Int {
        Int(canvasSize.width) * Int(canvasSize.height) * 4 * frames.count
    }
    init(frames: [CGImage], durations: [TimeInterval], canvasSize: CGSize) {
        self.frames = frames
        self.durations = durations
        self.totalDuration = durations.reduce(0, +)
        self.canvasSize = canvasSize
    }
}

enum APNGDecoder {

    private struct FrameSpec {
        var x = 0, y = 0, width = 0, height = 0
        var delay: TimeInterval = 0.1
        var dispose = 0   // 0 NONE / 1 BACKGROUND / 2 PREVIOUS
        var blend = 0     // 0 SOURCE / 1 OVER
        var imageData = Data()
    }

    static func decode(data: Data) -> APNGDecoded? {
        let bytes = [UInt8](data)
        guard bytes.count > 8,
              Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        else { return nil }

        func u32(_ b: [UInt8], _ off: Int) -> Int {
            (Int(b[off]) << 24) | (Int(b[off + 1]) << 16) | (Int(b[off + 2]) << 8) | Int(b[off + 3])
        }
        func u16(_ b: [UInt8], _ off: Int) -> Int {
            (Int(b[off]) << 8) | Int(b[off + 1])
        }

        var ihdr: [UInt8]?
        var plte: [UInt8]?
        var trns: [UInt8]?
        var specs: [FrameSpec] = []
        var sawAnimation = false

        var pos = 8
        while pos + 12 <= bytes.count {
            let length = u32(bytes, pos)
            guard pos + 12 + length <= bytes.count else { break }
            let type = String(bytes: bytes[(pos + 4)..<(pos + 8)], encoding: .ascii) ?? ""
            let chunkData = Array(bytes[(pos + 8)..<(pos + 8 + length)])
            switch type {
            case "IHDR":
                ihdr = chunkData
            case "PLTE":
                plte = chunkData
            case "tRNS":
                trns = chunkData
            case "acTL":
                sawAnimation = true
            case "fcTL":
                guard chunkData.count >= 26 else { return nil }
                var spec = FrameSpec()
                spec.width = u32(chunkData, 4)
                spec.height = u32(chunkData, 8)
                spec.x = u32(chunkData, 12)
                spec.y = u32(chunkData, 16)
                let num = u16(chunkData, 20)
                let denRaw = u16(chunkData, 22)
                let den = denRaw == 0 ? 100 : denRaw
                spec.delay = max(0.01, Double(num) / Double(den))
                spec.dispose = Int(chunkData[24])
                spec.blend = Int(chunkData[25])
                specs.append(spec)
            case "IDAT":
                // 默认图像即第一帧（fcTL 在 IDAT 之前）时归首帧；
                // 无 fcTL 的静态 PNG 走单帧路径（见函数尾）。
                if !specs.isEmpty {
                    specs[specs.count - 1].imageData.append(contentsOf: chunkData)
                }
            case "fdAT":
                guard chunkData.count > 4, !specs.isEmpty else { break }
                specs[specs.count - 1].imageData.append(contentsOf: chunkData[4...])
            case "IEND":
                pos = bytes.count
            default:
                break
            }
            pos += 12 + length
            if type == "IEND" { break }
        }

        guard let ihdr, ihdr.count >= 13 else { return nil }
        let canvasW = u32(ihdr, 0)
        let canvasH = u32(ihdr, 4)
        guard canvasW > 0, canvasH > 0 else { return nil }

        // 静态 PNG（无 acTL / 无帧定义）：整图作唯一帧。
        if !sawAnimation || specs.isEmpty {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return APNGDecoded(frames: [image], durations: [1],
                               canvasSize: CGSize(width: canvasW, height: canvasH))
        }

        // 逐帧重建独立 PNG 并解码。
        var frameImages: [CGImage] = []
        for spec in specs {
            guard spec.width > 0, spec.height > 0, !spec.imageData.isEmpty,
                  let png = buildPNG(ihdr: ihdr, plte: plte, trns: trns,
                                     width: spec.width, height: spec.height,
                                     idat: spec.imageData),
                  let source = CGImageSourceCreateWithData(png as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            frameImages.append(image)
        }

        // 合成全画布帧。
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: canvasW, height: canvasH,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(canvasH))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none

        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        for (index, spec) in specs.enumerated() {
            let rect = CGRect(x: spec.x, y: spec.y, width: spec.width, height: spec.height)
            let snapshot = spec.dispose == 2 ? ctx.makeImage() : nil
            ctx.saveGState()
            ctx.setBlendMode(spec.blend == 0 ? .copy : .normal)
            ctx.draw(frameImages[index], in: rect)
            ctx.restoreGState()
            guard let composited = ctx.makeImage() else { return nil }
            frames.append(composited)
            durations.append(spec.delay)
            switch spec.dispose {
            case 1: // BACKGROUND：该帧区域清空
                ctx.saveGState()
                ctx.clear(rect)
                ctx.restoreGState()
            case 2: // PREVIOUS：恢复到该帧绘制前
                if let snapshot {
                    ctx.saveGState()
                    ctx.setBlendMode(.copy)
                    ctx.draw(snapshot, in: CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
                    ctx.restoreGState()
                }
            default:
                break
            }
        }
        return APNGDecoded(frames: frames, durations: durations,
                           canvasSize: CGSize(width: canvasW, height: canvasH))
    }

    /// 以原 IHDR 的位深/色彩型 + 帧尺寸重建独立 PNG（单 IDAT）。
    private static func buildPNG(ihdr: [UInt8], plte: [UInt8]?, trns: [UInt8]?,
                                 width: Int, height: Int, idat: Data) -> Data? {
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var frameIHDR = ihdr
        frameIHDR[0] = UInt8((width >> 24) & 0xFF)
        frameIHDR[1] = UInt8((width >> 16) & 0xFF)
        frameIHDR[2] = UInt8((width >> 8) & 0xFF)
        frameIHDR[3] = UInt8(width & 0xFF)
        frameIHDR[4] = UInt8((height >> 24) & 0xFF)
        frameIHDR[5] = UInt8((height >> 16) & 0xFF)
        frameIHDR[6] = UInt8((height >> 8) & 0xFF)
        frameIHDR[7] = UInt8(height & 0xFF)
        appendChunk(&out, type: "IHDR", data: frameIHDR)
        if let plte { appendChunk(&out, type: "PLTE", data: plte) }
        if let trns { appendChunk(&out, type: "tRNS", data: trns) }
        appendChunk(&out, type: "IDAT", data: [UInt8](idat))
        appendChunk(&out, type: "IEND", data: [])
        return out
    }

    private static func appendChunk(_ out: inout Data, type: String, data: [UInt8]) {
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        let typeBytes = [UInt8](type.utf8)
        out.append(contentsOf: typeBytes)
        out.append(contentsOf: data)
        var crcInput = Data(typeBytes)
        crcInput.append(contentsOf: data)
        var crc = crc32([UInt8](crcInput)).bigEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// 解码缓存 + 后台解码（同名资产只解一次，多处共用）。
final class StickerStore {
    static let shared = StickerStore()

    private let cache = NSCache<NSString, APNGDecoded>()
    private var inFlight: [String: [(APNGDecoded?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "folia.sticker.decode", qos: .userInitiated)

    private init() {
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    /// 须在主线程调用（全部调用方都是 UI 代码）。
    func load(_ name: String, completion: @escaping (APNGDecoded?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let hit = cache.object(forKey: name as NSString) {
            completion(hit)
            return
        }
        if inFlight[name] != nil {
            inFlight[name]?.append(completion)
            return
        }
        inFlight[name] = [completion]
        queue.async { [weak self] in
            let decoded = Self.readAndDecode(name)
            DispatchQueue.main.async {
                guard let self else { return }
                if let decoded {
                    self.cache.setObject(decoded, forKey: name as NSString,
                                         cost: decoded.memoryCost)
                }
                let waiters = self.inFlight.removeValue(forKey: name) ?? []
                for waiter in waiters { waiter(decoded) }
            }
        }
    }

    private static func readAndDecode(_ name: String) -> APNGDecoded? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png",
                                        subdirectory: "Stickers"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return APNGDecoder.decode(data: data)
    }
}

/// 贴纸播放视图：帧序列由素材本体决定，本视图只按帧时长推进。
/// 模式：无限循环 / 播一次（停末帧或隐没由调用方处理）/ 播 N 圈。
final class StickerView: UIView {

    enum PlayMode: Equatable {
        case loop
        case once(holdLast: Bool)
        case loops(Int)
    }

    private let imageView = UIImageView()
    private var displayLink: CADisplayLink?
    private var decoded: APNGDecoded?
    private var frameIndex = 0
    private var frameElapsed: TimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var loopsDone = 0
    private var wantsPlaying = false

    private(set) var assetName: String?
    private(set) var playMode: PlayMode = .loop
    /// 播完回调（once / loops 模式；loop 模式不触发）。
    var onFinished: (() -> Void)?

    /// 狗贴纸（白底素材）置 true：本视图即浅色圆角贴纸底，
    /// 图内缩 4pt；猫（透明底）保持 false。
    var showsTileBackground = false {
        didSet { applyTileStyle() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        applyTileStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = showsTileBackground ? 4 : 0
        imageView.frame = bounds.insetBy(dx: inset, dy: inset)
    }

    private func applyTileStyle() {
        if showsTileBackground {
            backgroundColor = .white
            layer.cornerRadius = 12
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.25
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: 2)
        } else {
            backgroundColor = .clear
            layer.cornerRadius = 0
            layer.shadowOpacity = 0
        }
        setNeedsLayout()
    }

    /// 换贴纸（同名同模式重复调用只确保播放，不重解码不重置）。
    func setSticker(_ name: String, mode: PlayMode) {
        if assetName == name, playMode == mode, decoded != nil {
            play()
            return
        }
        assetName = name
        playMode = mode
        decoded = nil
        isFinished = false
        imageView.image = nil
        stopLink()
        StickerStore.shared.load(name) { [weak self] decoded in
            guard let self, self.assetName == name, let decoded else { return }
            self.decoded = decoded
            self.restart()
        }
    }

    func play() {
        wantsPlaying = true
        startLinkIfNeeded()
    }

    func pause() {
        wantsPlaying = false
        displayLink?.isPaused = true
    }

    /// 从第一帧重播（点按反应等只许用本体帧的场合）。
    func restart() {
        frameIndex = 0
        frameElapsed = 0
        loopsDone = 0
        lastTimestamp = 0
        isFinished = false
        showCurrentFrame()
        play()
    }

    func stopAndReset() {
        wantsPlaying = false
        stopLink()
        frameIndex = 0
        frameElapsed = 0
        loopsDone = 0
        isFinished = false
        showCurrentFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if decoded != nil && !isFinished { startLinkIfNeeded() }
        } else {
            displayLink?.isPaused = true
            lastTimestamp = 0
        }
    }

    private var isFinished = false

    private func startLinkIfNeeded() {
        guard decoded != nil, window != nil else { return }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = false
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
    }

    private func showCurrentFrame() {
        guard let decoded, decoded.frames.indices.contains(frameIndex) else { return }
        imageView.image = UIImage(cgImage: decoded.frames[frameIndex])
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let decoded, !decoded.frames.isEmpty, !isFinished else { return }
        if isHidden || alpha == 0 {
            lastTimestamp = 0
            return
        }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            showCurrentFrame()
            return
        }
        var dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        dt = min(dt, 0.1)
        frameElapsed += dt
        var advanced = false
        while frameElapsed >= decoded.durations[frameIndex] {
            frameElapsed -= decoded.durations[frameIndex]
            frameIndex += 1
            advanced = true
            if frameIndex >= decoded.frames.count {
                loopsDone += 1
                switch playMode {
                case .loop:
                    frameIndex = 0
                case .once(let holdLast):
                    frameIndex = decoded.frames.count - 1
                    frameElapsed = 0
                    isFinished = true
                    displayLink?.isPaused = true
                    if !holdLast { imageView.image = nil }
                    onFinished?()
                    return
                case .loops(let count):
                    if loopsDone >= count {
                        frameIndex = decoded.frames.count - 1
                        frameElapsed = 0
                        isFinished = true
                        displayLink?.isPaused = true
                        onFinished?()
                        return
                    }
                    frameIndex = 0
                }
            }
        }
        if advanced { showCurrentFrame() }
    }
}

/// 贴纸相关持久开关（陪伴宠物收起/放出跨启动保留）。
enum StickerSettings {
    private static let companionKey = "folia.stickers.companionEnabled"
    static var companionEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: companionKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: companionKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: companionKey) }
    }
}
