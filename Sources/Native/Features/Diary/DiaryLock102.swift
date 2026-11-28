import SwiftUI
import UIKit
import LocalAuthentication
import CryptoKit

// DiaryLock102.swift — (102) 第 2 项：日记隐私锁三法全上
// （数字密码＋手势图案＋Face ID）与字体签名存储、印章风
// 二维码生成。按过审样板定版：
// - 首次进入走设置向导：三种凭据全设（密码→手势→面容）
//   并选定一个首选解锁方式；
// - 之后解锁只先出首选，首选验证不过才弹出其他方式；
// - 凭据与首选可在使用中重设（书主页头部入口在
//   DiaryBookViews99 侧调 DiaryLockGate102.resetMode）。
// 密码/手势只存 SHA256 摘要（UserDefaults），不落明文。

enum DiaryLockMethod102: String, CaseIterable, Identifiable {
    case pin, pattern, face
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pin: return "数字密码"
        case .pattern: return "手势图案"
        case .face: return "面容 ID"
        }
    }
    var symbol: String {
        switch self {
        case .pin: return "keypad"
        case .pattern: return "hand.draw"
        case .face: return "faceid"
        }
    }
}

final class DiaryLockStore102: ObservableObject {
    static let shared = DiaryLockStore102()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let pinHash = "folia.diary102.lock.pinHash"
        static let patternHash = "folia.diary102.lock.patternHash"
        static let faceEnabled = "folia.diary102.lock.faceEnabled"
        static let preferred = "folia.diary102.lock.preferred"
        static let configured = "folia.diary102.lock.configured"
    }

    @Published private(set) var configured: Bool
    @Published private(set) var preferred: DiaryLockMethod102

    private init() {
        configured = defaults.bool(forKey: Key.configured)
        preferred = DiaryLockMethod102(
            rawValue: defaults.string(forKey: Key.preferred) ?? "") ?? .face
    }

    var faceEnabled: Bool { defaults.bool(forKey: Key.faceEnabled) }
    var hasPin: Bool { defaults.string(forKey: Key.pinHash) != nil }
    var hasPattern: Bool { defaults.string(forKey: Key.patternHash) != nil }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }
            .joined()
    }

    func setPin(_ pin: String) {
        defaults.set(Self.hash("pin:" + pin), forKey: Key.pinHash)
    }
    func verifyPin(_ pin: String) -> Bool {
        defaults.string(forKey: Key.pinHash) == Self.hash("pin:" + pin)
    }
    func setPattern(_ points: [Int]) {
        defaults.set(Self.hash("pat:" + points.map(String.init).joined(separator: ",")),
                     forKey: Key.patternHash)
    }
    func verifyPattern(_ points: [Int]) -> Bool {
        defaults.string(forKey: Key.patternHash)
            == Self.hash("pat:" + points.map(String.init).joined(separator: ","))
    }
    func setFaceEnabled(_ on: Bool) {
        defaults.set(on, forKey: Key.faceEnabled)
    }
    func finishConfiguration(preferred: DiaryLockMethod102) {
        self.preferred = preferred
        defaults.set(preferred.rawValue, forKey: Key.preferred)
        configured = true
        defaults.set(true, forKey: Key.configured)
        Breadcrumbs.log("p102 diary lock configured pref=\(preferred.rawValue)")
    }
    func resetAll() {
        for key in [Key.pinHash, Key.patternHash, Key.faceEnabled,
                    Key.preferred, Key.configured] {
            defaults.removeObject(forKey: key)
        }
        configured = false
        preferred = .face
        Breadcrumbs.log("p102 diary lock reset")
    }
}

// MARK: - 手势图案格（3×3，设置与验证共用）

struct DiaryPatternGrid102: View {
    /// 完成一条图案（≥4 点）时回调；验证态画完即回调。
    let onComplete: ([Int]) -> Void
    /// 外部重置信号（递增即清格）。
    let resetToken: Int
    @State private var points: [Int] = []

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 3
            ZStack {
                // 连线
                Path { path in
                    for (i, idx) in points.enumerated() {
                        let p = center(idx, cell: cell)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(DiaryPaper99.accent, style: StrokeStyle(
                    lineWidth: 3, lineCap: .round, lineJoin: .round))
                ForEach(0..<9, id: \.self) { idx in
                    let c = center(idx, cell: cell)
                    Circle()
                        .fill(points.contains(idx)
                              ? DiaryPaper99.accent : DiaryPaper99.dim.opacity(0.35))
                        .frame(width: points.contains(idx) ? 20 : 14,
                               height: points.contains(idx) ? 20 : 14)
                        .position(c)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let idx = hit(value.location, cell: cell),
                           !points.contains(idx) {
                            points.append(idx)
                        }
                    }
                    .onEnded { _ in
                        if points.count >= 4 { onComplete(points) }
                        points = []
                    })
            .onChange(of: resetToken) { _, _ in points = [] }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func center(_ idx: Int, cell: CGFloat) -> CGPoint {
        CGPoint(x: cell * (CGFloat(idx % 3) + 0.5),
                y: cell * (CGFloat(idx / 3) + 0.5))
    }
    private func hit(_ point: CGPoint, cell: CGFloat) -> Int? {
        for idx in 0..<9 {
            let c = center(idx, cell: cell)
            if hypot(point.x - c.x, point.y - c.y) < cell * 0.42 { return idx }
        }
        return nil
    }
}

// MARK: - 锁门（向导 / 锁屏，宿主 VC 只管进书回调）

struct DiaryLockGate102: View {
    let onUnlock: () -> Void
    let onClose: () -> Void
    @ObservedObject private var store = DiaryLockStore102.shared
    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.15, blue: 0.20).ignoresSafeArea()
            if store.configured {
                DiaryLockScreen102(onUnlock: onUnlock, onClose: onClose)
            } else {
                DiaryLockWizard102(onDone: onUnlock, onClose: onClose)
            }
        }
    }
}

/// 首次向导：密码 → 手势 → 面容 → 选首选，四步逐步存档。
private struct DiaryLockWizard102: View {
    let onDone: () -> Void
    let onClose: () -> Void
    @ObservedObject private var store = DiaryLockStore102.shared
    @State private var step = 0
    @State private var pin = ""
    @State private var pinConfirm = ""
    @State private var pinStage = 0 // 0 输入、1 确认
    @State private var patternStage = 0
    @State private var firstPattern: [Int] = []
    @State private var patternReset = 0
    @State private var faceDone = false
    @State private var preferred: DiaryLockMethod102 = .face
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                }
            }
            Image(systemName: "lock.fill")
                .font(.system(size: 40)).foregroundColor(.white.opacity(0.9))
            Text("设置日记锁").font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
            Text("第 \(step + 1) 步 / 共 4 步 · \(stepTitle)")
                .font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6))
            if let message {
                Text(message).font(.system(size: 13))
                    .foregroundColor(Color(red: 1, green: 0.65, blue: 0.5))
            }
            content
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var stepTitle: String {
        ["设置数字密码", "设置手势图案", "开启面容 ID", "选择首选解锁方式"][step]
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(spacing: 14) {
                SecureField(pinStage == 0 ? "输入 4–6 位密码" : "再输一次确认",
                            text: pinStage == 0 ? $pin : $pinConfirm)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.10)))
                Button(pinStage == 0 ? "下一步" : "确认密码") { submitPin() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Capsule().fill(DiaryPaper99.accent))
            }
        case 1:
            VStack(spacing: 10) {
                Text(patternStage == 0 ? "连出你的图案（至少 4 个点）" : "再连一次确认")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
                DiaryPatternGrid102(onComplete: submitPattern,
                                    resetToken: patternReset)
                    .frame(width: 240, height: 240)
            }
        case 2:
            VStack(spacing: 14) {
                Text("用面容 ID 快速解锁这本日记")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.75))
                Button(faceDone ? "已开启 ✓" : "开启面容 ID") { enableFace() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Capsule().fill(DiaryPaper99.accent))
                Button("跳过这一步") {
                    store.setFaceEnabled(false)
                    step = 3
                }
                .font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
            }
        default:
            VStack(spacing: 12) {
                ForEach(DiaryLockMethod102.allCases.filter {
                    $0 != .face || store.faceEnabled
                }) { method in
                    Button {
                        preferred = method
                    } label: {
                        HStack {
                            Image(systemName: method.symbol)
                            Text(method.title)
                            Spacer()
                            if preferred == method {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(
                                preferred == method ? 0.22 : 0.08)))
                    }
                }
                Button("完成设置，进入日记") {
                    store.finishConfiguration(preferred: preferred)
                    onDone()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 26).padding(.vertical, 11)
                .background(Capsule().fill(DiaryPaper99.accent))
                .padding(.top, 6)
            }
        }
    }

    private func submitPin() {
        if pinStage == 0 {
            guard (4...6).contains(pin.count), pin.allSatisfy(\.isNumber) else {
                message = "密码须为 4–6 位数字"
                return
            }
            pinStage = 1
            message = nil
        } else {
            guard pinConfirm == pin else {
                message = "两次输入不一致，请重设"
                pin = ""; pinConfirm = ""; pinStage = 0
                return
            }
            store.setPin(pin)
            step = 1
            message = nil
        }
    }

    private func submitPattern(_ points: [Int]) {
        if patternStage == 0 {
            firstPattern = points
            patternStage = 1
            patternReset += 1
        } else {
            guard points == firstPattern else {
                message = "两次图案不一致，请重设"
                patternStage = 0
                patternReset += 1
                return
            }
            store.setPattern(points)
            step = 2
            message = nil
        }
    }

    private func enableFace() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            message = "这台设备没有可用的面容 ID，可跳过这一步"
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "为音乐日记本开启面容解锁") { success, _ in
            DispatchQueue.main.async {
                if success {
                    store.setFaceEnabled(true)
                    faceDone = true
                    message = nil
                    step = 3
                } else {
                    message = "面容验证未通过，可重试或跳过"
                }
            }
        }
    }
}

/// 锁屏：只先出首选；首选失败（或点「其他方式」兜底出
/// 现后）才列其他方式——与样板定版一致：其他方式入口
/// 在首次失败后出现。
private struct DiaryLockScreen102: View {
    let onUnlock: () -> Void
    let onClose: () -> Void
    @ObservedObject private var store = DiaryLockStore102.shared
    @State private var active: DiaryLockMethod102?
    @State private var showOthers = false
    @State private var pin = ""
    @State private var patternReset = 0
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                }
            }
            Image(systemName: "lock.fill")
                .font(.system(size: 40)).foregroundColor(.white.opacity(0.9))
            Text("音乐日记本").font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
            Text("这是只属于你的私密记录")
                .font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6))
            if let message {
                Text(message).font(.system(size: 13))
                    .foregroundColor(Color(red: 1, green: 0.65, blue: 0.5))
            }
            methodBody
            if showOthers {
                HStack(spacing: 10) {
                    ForEach(otherMethods, id: \.self) { method in
                        Button {
                            active = method
                            message = nil
                            if method == .face { tryFace() }
                        } label: {
                            Label(method.title, systemImage: method.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .onAppear {
            active = store.preferred
            if store.preferred == .face { tryFace() }
        }
    }

    private var otherMethods: [DiaryLockMethod102] {
        DiaryLockMethod102.allCases.filter { method in
            method != (active ?? store.preferred) && available(method)
        }
    }

    private func available(_ method: DiaryLockMethod102) -> Bool {
        switch method {
        case .pin: return store.hasPin
        case .pattern: return store.hasPattern
        case .face: return store.faceEnabled
        }
    }

    @ViewBuilder
    private var methodBody: some View {
        switch active ?? store.preferred {
        case .pin:
            VStack(spacing: 14) {
                SecureField("输入数字密码", text: $pin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.10)))
                Button("解锁") {
                    if store.verifyPin(pin) {
                        onUnlock()
                    } else {
                        pin = ""
                        fail("密码不对")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 26).padding(.vertical, 11)
                .background(Capsule().fill(DiaryPaper99.accent))
            }
        case .pattern:
            VStack(spacing: 10) {
                Text("连出你的图案").font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                DiaryPatternGrid102(onComplete: { points in
                    if store.verifyPattern(points) {
                        onUnlock()
                    } else {
                        patternReset += 1
                        fail("图案不对")
                    }
                }, resetToken: patternReset)
                .frame(width: 240, height: 240)
            }
        case .face:
            VStack(spacing: 14) {
                Image(systemName: "faceid")
                    .font(.system(size: 44)).foregroundColor(.white.opacity(0.9))
                Button("面容 ID 解锁") { tryFace() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Capsule().fill(DiaryPaper99.accent))
            }
        }
    }

    private func fail(_ text: String) {
        message = text
        // 首选验证不过 → 弹出其他方式（样板定版）。
        showOthers = true
        Breadcrumbs.log("p102 diary lock fail others=\(showOthers ? 1 : 0)")
    }

    private func tryFace() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            fail("面容 ID 不可用")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "解锁你的音乐日记本") { success, _ in
            DispatchQueue.main.async {
                if success { onUnlock() } else { fail("面容验证未通过") }
            }
        }
    }
}

// MARK: - 字体签名（双通道之二，独立落盘）

/// 字体签名：打字生成、选字体、手写通道并存；当前签名
/// 通道（hand/font）决定打印落款用哪份。
final class DiaryFontSignature102: ObservableObject {
    static let shared = DiaryFontSignature102()

    /// 可选字体（运行时按设备可用性过滤）：手写体优先。
    static let candidateFonts = [
        "HanziPen SC", "Wawati SC", "Yuppy SC",
        "Bradley Hand", "Snell Roundhand", "Kaiti SC",
    ]
    static var availableFonts: [String] {
        candidateFonts.filter { UIFont(name: $0, size: 20) != nil }
    }

    @Published var text: String {
        didSet { defaults.set(text, forKey: Key.text) }
    }
    @Published var fontName: String {
        didSet { defaults.set(fontName, forKey: Key.font) }
    }
    /// "hand" | "font"：落款通道。
    @Published var channel: String {
        didSet { defaults.set(channel, forKey: Key.channel) }
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let text = "folia.diary102.fontsig.text"
        static let font = "folia.diary102.fontsig.font"
        static let channel = "folia.diary102.fontsig.channel"
    }

    private init() {
        text = defaults.string(forKey: Key.text) ?? ""
        fontName = defaults.string(forKey: Key.font)
            ?? Self.availableFonts.first ?? "Bradley Hand"
        channel = defaults.string(forKey: Key.channel) ?? "hand"
    }

    var hasFontSignature: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - 印章风二维码（单墨色、真可扫）

enum DiaryQRCode102 {
    private static var cache: [String: UIImage] = [:]

    /// 由短链生成单色二维码图（最近邻放大、不糊码眼）。
    static func image(for string: String, ink: UIColor, size: CGFloat = 220) -> UIImage? {
        let cacheKey = string + "|" + String(describing: ink)
        if let hit = cache[cacheKey] { return hit }
        let made = makeImage(for: string, ink: ink, size: size)
        if let made { cache[cacheKey] = made }
        return made
    }

    private static func makeImage(for string: String, ink: UIColor, size: CGFloat) -> UIImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(string.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // 单墨色化：白底透出纸色、码眼染墨色。
        let colorFilter = CIFilter(name: "CIFalseColor")
        colorFilter?.setValue(scaled, forKey: "inputImage")
        colorFilter?.setValue(CIColor(color: ink), forKey: "inputColor0")
        colorFilter?.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0),
                               forKey: "inputColor1")
        guard let colored = colorFilter?.outputImage else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(colored, from: colored.extent)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 条目短链（访客页地址的编码源；扫码打开这一页）。
    static func shortLink(for entryId: String) -> String {
        "virelai.app/d/\(entryId.prefix(8).lowercased())"
    }
    static func shortURL(for entryId: String) -> String {
        "https://" + shortLink(for: entryId)
    }
    /// 页脚序号：由条目 id 确定性派生（同条目恒同号）。
    static func serial(for entryId: String) -> String {
        var acc = 0
        for scalar in entryId.unicodeScalars {
            acc = (acc * 31 + Int(scalar.value)) % 10000
        }
        return String(format: "Nº %04d", acc)
    }
}

// MARK: - 抱心狗定格帧 + APNG 承载视图 + 正文字体

/// 抱心狗（dog-11 APNG）定格帧：进日记时预解码，取中段
/// 帧作「正面抱心」定格（打印/静态呈现用）；动效呈现走
/// DiaryAPNGStickerView102 的 StickerView 循环播放。
enum DiaryDogFrame102 {
    private(set) static var image: UIImage?
    private static var loading = false

    static func preload() {
        guard image == nil, !loading else { return }
        loading = true
        StickerStore.shared.load("dog-11") { decoded in
            loading = false
            guard let decoded, !decoded.frames.isEmpty else { return }
            image = UIImage(cgImage: decoded.frames[decoded.frames.count / 2])
            Breadcrumbs.log("p102 diary dog frame ready frames=\(decoded.frames.count)")
        }
    }
}

/// SwiftUI 承载 StickerView（APNG 循环）。
struct DiaryAPNGStickerView102: UIViewRepresentable {
    let name: String
    func makeUIView(context: Context) -> StickerView {
        let view = StickerView()
        view.backgroundColor = .clear
        view.setSticker(name, mode: .loop)
        return view
    }
    func updateUIView(_ view: StickerView, context: Context) {
        view.setSticker(name, mode: .loop)
    }
}

/// 正文字体（102 第 2 项：编辑态可选、随条目持久化、
/// 打印按所选字体输出）。默认 Songti SC。
enum DiaryBodyFont102 {
    static let candidates = ["Songti SC", "Kaiti SC", "HanziPen SC",
                             "Wawati SC", "Yuppy SC"]
    static var available: [String] {
        candidates.filter { UIFont(name: $0, size: 16) != nil }
    }
    static func font(name: String?, size: CGFloat) -> Font {
        if let name, available.contains(name) {
            return .custom(name, size: size)
        }
        return .custom("Songti SC", size: size)
    }
    static func displayName(_ name: String?) -> String {
        name ?? "Songti SC"
    }
}
