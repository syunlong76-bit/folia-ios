import Foundation
import Metal
import MetalKit
import simd
import UIKit

// (103) 圣诞场景 Metal 引擎：MTKView（paused、宿主 frameTick
// 驱动）＋ HDR 场景 RT（RGBA16Float＋depth32Float）＋ bloom
// mip 链 ＋ ACES/sRGB 终程。相机 rig 与手势统一分发逐式移植
// 样板（拖拽轨道/双指 spread+半径/点按 ripple+雪沫/拖动搅雪
// 共用同一套手势入口）。绘制纪律（DS 对账）：in-flight 闸
// （信号量满时跳过本帧、只存最新 position）；尺寸变化下一帧
// 重建 RT；借粒 buffer 预分配、只在换行时写入。

// MARK: - uniform 镜像（与 XmasShaders103 布局逐字段对齐）

struct XmasFrameU103 {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var camPos = SIMD4<Float>(0, 0, 0, 0)
    var time: Float = 0
}

struct XmasPoolU103 {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var uTime: Float = 0
    var uSpread: Float = 0
    var uPR: Float = 1
    var uSnow: Float = 0
    var uRipplePos = SIMD4<Float>(0, 0, 0, 0)
    var uRippleT: Float = -1
    var uFly: Float = 0
    var uReturn: Float = 0
    var padA: Float = 0
    var uLyrPos = SIMD4<Float>(0, 0, 0, 0)
    var uLyrCos: Float = 1
    var uLyrSin: Float = 0
    var uCharLit: Float = 99
    var uBreath: Float = 0
    var uWindDir = SIMD4<Float>(0.85, 0.2, 0.3, 0)
    var uWindAmt: Float = 0.9
    var uRibbonAmp: Float = 0.07
    var uGust: Float = 0
    var uOpacity: Float = 1
    var pad0: Float = 0
    var pad1: Float = 0
}

struct XmasLightsU103 {
    var hemiSky = SIMD4<Float>(0, 0, 0, 0)
    var hemiGround = SIMD4<Float>(0, 0, 0, 0)
    var moonDir = SIMD4<Float>(0, 1, 0, 0)
    var moonColor = SIMD4<Float>(0, 0, 0, 0)
    var rimDir = SIMD4<Float>(0, 1, 0, 0)
    var rimColor = SIMD4<Float>(0, 0, 0, 0)
    var ptPos: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0))
    var ptColor: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
        (SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0))
}

struct XmasEntGroupU103 {
    var baseColor = SIMD4<Float>(1, 1, 1, 1)
    var emissive = SIMD4<Float>(0, 0, 0, 0)
    var roughMetal = SIMD2<Float>(1, 0)
    var useTex: Float = 0
    var pad: Float = 0
}

struct XmasSnowU103 {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var camPos = SIMD4<Float>(0, 0, 0, 0)
    var uTime: Float = 0
    var uPR: Float = 1
    var uMode: Float = 0
    var uOpacity: Float = 1
    var pad: Float = 0
}

struct XmasSprU103 {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
}

struct XmasSprInst103 {
    var center = SIMD3<Float>(0, 0, 0)
    var size = SIMD2<Float>(1, 1)
    var color = SIMD4<Float>(1, 1, 1, 1)
}

struct XmasDiscInst103 {
    var center = SIMD3<Float>(0, 0, 0)
    var size = SIMD2<Float>(1, 1)
    var rotY: Float = 0
    var color = SIMD4<Float>(1, 1, 1, 1)
}

struct XmasBloomU103 {
    var threshold: Float = 0.9
    var knee: Float = 0.1
    var texel = SIMD2<Float>(0, 0)
    var dir = SIMD2<Float>(1, 0)
    var weight: Float = 1
    var pad0: Float = 0
    var pad1: Float = 0
}

struct XmasFinalU103 {
    var bloomStrength: Float = 0.5
    var exposure: Float = 0.85
    var pad = SIMD2<Float>(0, 0)
}

// MARK: - 画布视图（paused；draw 由宿主 tick 触发）

final class XmasMetalView103: MTKView {
    var onDrawFrame: (() -> Void)?
    var onResize: (() -> Void)?
    override func draw(_ rect: CGRect) { onDrawFrame?() }
    override func layoutSubviews() {
        super.layoutSubviews()
        onResize?()
    }
}

// MARK: - 引擎

final class XmasMetalEngine103: NSObject, UIGestureRecognizerDelegate {
    let view: XmasMetalView103

    private let device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var library: MTLLibrary?
    private var sampler: MTLSamplerState?

    private var pipeEntOpaque: MTLRenderPipelineState?
    private var pipeEntBlend: MTLRenderPipelineState?
    private var pipePool: MTLRenderPipelineState?
    private var pipeSnow: MTLRenderPipelineState?
    private var pipeSprAdd: MTLRenderPipelineState?
    private var pipeSprNorm: MTLRenderPipelineState?
    private var pipeDiscShadow: MTLRenderPipelineState?
    private var pipeDiscAdd: MTLRenderPipelineState?
    private var pipeBright: MTLRenderPipelineState?
    private var pipeBlur: MTLRenderPipelineState?
    private var pipeDown: MTLRenderPipelineState?
    private var pipeFinal: MTLRenderPipelineState?
    private var depthOn: MTLDepthStencilState?
    private var depthOff: MTLDepthStencilState?

    // 贴图槽：0 soft、1 star、2 shadow、3 poolColor、4 poolWhite、5 shade、6 crystal、7+ GLB
    private var textures: [MTLTexture?] = []
    private var texWhite: MTLTexture?

    private var baked: XmasBakedScene103?
    private var entPos: MTLBuffer?
    private var entNrm: MTLBuffer?
    private var entUV: MTLBuffer?
    private var entCol: MTLBuffer?
    private var entIdx: MTLBuffer?

    private struct PoolGPU {
        var pos: MTLBuffer?
        var col: MTLBuffer?
        var misc1: MTLBuffer?
        var dir: MTLBuffer?
        var count: Int = 0
        var opacity: Float = 1
        var snowMode: Bool = false
    }
    private var poolOrbit = PoolGPU()
    private var poolTrunk = PoolGPU()
    private var poolCanopy = PoolGPU()
    private var poolSparkle = PoolGPU()
    private var poolSky = PoolGPU()
    private var poolFarSnow = PoolGPU()
    private var lyrBuf: MTLBuffer?
    private var misc2Buf: MTLBuffer?
    private var misc2Zero: MTLBuffer?

    private var snowSim: XmasSnowSim103?
    private var fallPosBuf: MTLBuffer?
    private var fallMiscBuf: MTLBuffer?
    private var accPosBuf: MTLBuffer?
    private var accMiscBuf: MTLBuffer?
    private var accLifeBuf: MTLBuffer?

    private let lyricMachine = XmasLyricMachine103()
    private var lines: [LyricLine] = []
    private var trackId: String? = nil
    private var active = false
    private var ready = false

    // 时钟（宿主 tick 累计；停 tick 即冻结，与样板 perfNow 口径一致地单调）
    private var time: Float = 0
    private var lastTickWall: TimeInterval? = nil
    private var latestPosition: TimeInterval = 0

    // 相机 rig（样板 applyCamera 同构）
    private var rigTheta: Float = 0.567, rigPhi: Float = 1.516, rigRadius: Float = 22
    private var rigTTheta: Float = 0.567, rigTPhi: Float = 1.516, rigTRadius: Float = 22
    private var velTheta: Float = 0, velPhi: Float = 0
    private var lastTouch: Float = -100
    private var fovDeg: Float = 40
    private var aspectTier: Int = -1
    private let camTarget = SIMD3<Float>(1.2, 3.6, -0.7)
    private var followDTheta: Float = 0
    private var followPhi: Float = 1.35
    private var followRadius: Float = 20
    private var followFocus = SIMD3<Float>(1.2, 3.6, -0.7)
    private var followAllowed = true
    private var followGoal: Float = 0
    private var followCur: Float = 0
    var frameDt: Float = 1.0 / 60.0
    var lookTarget = SIMD3<Float>(1.2, 3.6, -0.7)
    private var camPos = SIMD3<Float>(0, 4, 22)
    private var camView = matrix_identity_float4x4
    private var camProj = matrix_identity_float4x4

    // 手势状态
    private var dragging = false
    private var pinching = false
    private var lastPan = CGPoint.zero
    private var lastPanT: TimeInterval = 0
    private var lastPinchScale: CGFloat = 1
    private var spreadTarget: Float = 0
    private var spreadCur: Float = 0
    private var pinchSnowTarget: Float = 0
    private var pinchSnow: Float = 0
    private var rippleStart: Float = -10
    private var ripplePos = SIMD3<Float>(0, 4.2, 0)

    // RT
    private var hdrRT: MTLTexture?
    private var depthRT: MTLTexture?
    private var bloomTex: [[MTLTexture?]] = [[nil, nil], [nil, nil], [nil, nil]]  // 3 级 × pingpong
    private var rtSize = CGSize.zero
    private var rtBytes: Int = 0

    private let inflight = DispatchSemaphore(value: 3)
    private var firstFrameLogged = false
    private var fpsAccum: TimeInterval = 0
    private var fpsFrames = 0
    private var fpsWindow: TimeInterval = 0
    private var lastAnchorName = ""

    // (105) 性能隔离：宿主 frameTick 走主线程（CADisplayLink），
    // (103) 把落雪模拟＋字形采样＋全部编码都压在主线程，场景一
    // 重就拖垮全 App。落雪模拟与字形采样改到本队列异步执行，
    // tick 线程只消费快照（memcpy 小数组）；编码仍在 tick 线程
    // （MTKView draw 纪律），其耗时由 perf 面包屑逐项落痕。
    private let simQueue = DispatchQueue(label: "folia.xmas.sim105", qos: .userInitiated)
    private let snapLock = NSLock()
    private var simBusy = false
    private var snapFallPos: [Float] = []
    private var snapFallMisc: [Float] = []
    private var snapAccPos: [Float] = []
    private var snapAccMisc: [Float] = []
    private var snapAccLife: [Float] = []
    private var snapFallDirty = false
    private var snapAccDirty = false
    private var snapGust: Float = 0
    private var lastGust: Float = 0
    private var sampleInFlight = -1
    private var sampleFlightDone = true   // snapLock 保护；防过期采样覆盖新行结果后无人重派
    // perf 窗口（与 fps 同 5s 窗）：tick 线程编码耗时均值/峰值、
    // 后台模拟峰值、字形采样峰值（毫秒）。
    private var perfEncSum: Double = 0
    private var perfEncMax: Double = 0
    private var perfEncN: Int = 0
    private var perfSimMax: Double = 0
    private var perfAssignMax: Double = 0

    override init() {
        let dev = MTLCreateSystemDefaultDevice()
        device = dev
        view = XmasMetalView103(frame: .zero, device: dev)
        super.init()
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.002, green: 0.004, blue: 0.010, alpha: 1)
        view.backgroundColor = UIColor(red: 0.002, green: 0.004, blue: 0.010, alpha: 1)
        view.isUserInteractionEnabled = true
        view.onDrawFrame = { [weak self] in self?.render() }
        view.onResize = { [weak self] in self?.noteResize() }
        queue = dev?.makeCommandQueue()
        if let dev {
            library = try? dev.makeLibrary(source: XmasShaders103.source, options: nil)
            if library == nil {
                Breadcrumbs.log("p105 xmas shader lib=nil")
            }
        }
        buildPipelines()
        buildProceduralTextures()
        installGestures()
    }

    // MARK: 管线

    private func makePipe(_ vfn: String, _ ffn: String, format: MTLPixelFormat,
                          blend: (MTLBlendOperation, MTLBlendFactor, MTLBlendFactor)?,
                          depth: Bool) -> MTLRenderPipelineState? {
        guard let library, let device,
              let v = library.makeFunction(name: vfn),
              let f = library.makeFunction(name: ffn) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = v
        d.fragmentFunction = f
        guard let ca = d.colorAttachments[0] else { return nil }
        ca.pixelFormat = format
        if let (op, src, dst) = blend {
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = op
            ca.alphaBlendOperation = op
            ca.sourceRGBBlendFactor = src
            ca.destinationRGBBlendFactor = dst
            ca.sourceAlphaBlendFactor = src
            ca.destinationAlphaBlendFactor = dst
        }
        if depth { d.depthAttachmentPixelFormat = .depth32Float }
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    private func buildPipelines() {
        guard let device else { return }
        let add: (MTLBlendOperation, MTLBlendFactor, MTLBlendFactor) = (.add, .sourceAlpha, .one)
        let norm: (MTLBlendOperation, MTLBlendFactor, MTLBlendFactor) = (.add, .sourceAlpha, .oneMinusSourceAlpha)
        pipeEntOpaque = makePipe("entVert", "entFrag", format: .rgba16Float, blend: nil, depth: true)
        pipeEntBlend = makePipe("entVert", "entFrag", format: .rgba16Float, blend: norm, depth: true)
        pipePool = makePipe("poolVert", "poolFrag", format: .rgba16Float, blend: add, depth: true)
        pipeSnow = makePipe("snowVert", "snowFrag", format: .rgba16Float, blend: norm, depth: true)
        pipeSprAdd = makePipe("sprVert", "sprFrag", format: .rgba16Float, blend: add, depth: true)
        pipeSprNorm = makePipe("sprVert", "sprFrag", format: .rgba16Float, blend: norm, depth: true)
        pipeDiscShadow = makePipe("discVert", "discFrag", format: .rgba16Float, blend: norm, depth: true)
        pipeDiscAdd = makePipe("discVert", "discFrag", format: .rgba16Float, blend: add, depth: true)
        pipeBright = makePipe("quadVert", "brightFrag", format: .rgba16Float, blend: nil, depth: false)
        pipeBlur = makePipe("quadVert", "blurFrag", format: .rgba16Float, blend: nil, depth: false)
        pipeDown = makePipe("quadVert", "downFrag", format: .rgba16Float, blend: nil, depth: false)
        pipeFinal = makePipe("quadVert", "finalFrag", format: .bgra8Unorm, blend: nil, depth: false)
        let ddOn = MTLDepthStencilDescriptor()
        ddOn.depthCompareFunction = .less
        ddOn.isDepthWriteEnabled = true
        depthOn = device.makeDepthStencilState(descriptor: ddOn)
        let ddOff = MTLDepthStencilDescriptor()
        ddOff.depthCompareFunction = .less
        ddOff.isDepthWriteEnabled = false
        depthOff = device.makeDepthStencilState(descriptor: ddOff)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sd)
        Breadcrumbs.log("p105 xmas pipes ent=\(pipeEntOpaque != nil ? 1 : 0) pool=\(pipePool != nil ? 1 : 0) final=\(pipeFinal != nil ? 1 : 0)")
    }

    // MARK: 程序化贴图（逐像素生成，口径对样板 canvas 渐变）

    private func makeTexture(w: Int, h: Int, srgb: Bool,
                             _ px: (Int, Int) -> (Float, Float, Float, Float)) -> MTLTexture? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b, a) = px(x, y)
                let o = (y * w + x) * 4
                bytes[o] = UInt8(min(max(r, 0), 1) * 255)
                bytes[o + 1] = UInt8(min(max(g, 0), 1) * 255)
                bytes[o + 2] = UInt8(min(max(b, 0), 1) * 255)
                bytes[o + 3] = UInt8(min(max(a, 0), 1) * 255)
            }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: srgb ? .rgba8Unorm_srgb : .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        bytes.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: w * 4)
        }
        return tex
    }

    private func radial(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Float {
        let dx = (Float(x) / Float(w) - 0.5) * 2
        let dy = (Float(y) / Float(h) - 0.5) * 2
        return sqrt(dx * dx + dy * dy)
    }

    private func buildProceduralTextures() {
        // 0 soft（glowTexture(false)：1 → 0.4@0.25 → 0）
        let soft = makeTexture(w: 256, h: 256, srgb: true) { [self] x, y in
            let r = radial(x, y, 256, 256)
            let a: Float = r < 0.25 ? 1 - (1 - 0.4) * (r / 0.25) : max(0, 0.4 * (1 - (r - 0.25) / 0.75))
            return (1, 1, 1, a)
        }
        // 1 star（glowTexture(true)：径向晕＋十字芒＋五角星＋亮芯）
        let star = makeTexture(w: 512, h: 512, srgb: true) { x, y in
            let fx = Float(x) - 256, fy = Float(y) - 256
            let r = sqrt(fx * fx + fy * fy) / 256
            var cr: Float = 1.0, cg: Float = 0.94, cb: Float = 0.78, ca: Float
            if r < 0.35 { ca = 0.55 + (0.18 - 0.55) * (r / 0.35) }
            else { ca = max(0, 0.18 * (1 - (r - 0.35) / 0.65)) }
            // 十字芒（横/竖各一条，沿轴渐变、厚 6px）
            let gx = max(0, 1 - abs(fx) / 300)
            let glintX = (1 - pow(gx, 1.0)) * 0 + (gx < 0.5 ? gx * 2 * 0.5 : (1 - gx) * 2 * 0.5 + 0) // 三角波近似画布线性渐变
            _ = glintX
            let barH = abs(fy) <= 3 ? (0.5 * (1 - abs(fx) / 300)) : Float(0)
            let barV = abs(fx) <= 3 ? (0.5 * (1 - abs(fy) / 300)) : Float(0)
            let ga = max(barH, barV)
            if ga > ca { cr = 1.0; cg = 0.95; cb = 0.80; ca = max(ca, ga) }
            // 五角星（画布同式：外 118 / 内 46、顶点朝上）
            var inside = false
            do {
                var verts: [(Float, Float)] = []
                for i in 0..<10 {
                    let rr: Float = i % 2 == 0 ? 118 : 46
                    let a = -Float.pi / 2 + Float(i) * Float.pi / 5
                    verts.append((cos(a) * rr, sin(a) * rr))
                }
                var c = false
                for i in 0..<10 {
                    let (x1, y1) = verts[i]
                    let (x2, y2) = verts[(i + 1) % 10]
                    if (y1 > fy) != (y2 > fy) {
                        let xi = x1 + (fy - y1) / (y2 - y1) * (x2 - x1)
                        if fx < xi { c = !c }
                    }
                }
                inside = c
            }
            if inside { return (1.0, 0.965, 0.86, 1.0) }
            let dc = sqrt(fx * fx + fy * fy)
            if dc < 20 { return (1, 1, 1, 0.98) }
            return (cr, cg, cb, ca)
        }
        // 2 shadow（接地阴影径向黑）
        let shadow = makeTexture(w: 256, h: 256, srgb: true) { [self] x, y in
            let r = radial(x, y, 256, 256)
            let a: Float = r < 0.6 ? 0.85 - (0.85 - 0.4) * (r / 0.6) : max(0, 0.4 * (1 - (r - 0.6) / 0.4))
            return (0, 0, 0, a)
        }
        // 3 poolColor（树下暖池：rgb 255,196,116；a 0.62→0.22@0.55→0）
        let poolC = makeTexture(w: 256, h: 256, srgb: true) { [self] x, y in
            let r = radial(x, y, 256, 256)
            let a: Float = r < 0.55 ? 0.62 - (0.62 - 0.22) * (r / 0.55) : max(0, 0.22 * (1 - (r - 0.55) / 0.45))
            return (1.0, 0.77, 0.45, a)
        }
        // 4 poolWhite（暖池通用：白 rgb、a 0.9→0.35@0.55→0，靠 disc 色染暖）
        let poolW = makeTexture(w: 256, h: 256, srgb: true) { [self] x, y in
            let r = radial(x, y, 256, 256)
            let a: Float = r < 0.55 ? 0.9 - (0.9 - 0.35) * (r / 0.55) : max(0, 0.35 * (1 - (r - 0.55) / 0.45))
            return (1, 1, 1, a)
        }
        // 5 shade（歌词衬底暗椭圆：darkEllipseTexture 同式）
        let shade = makeTexture(w: 256, h: 128, srgb: true) { x, y in
            let dx = (Float(x) - 128) / 120
            let dy = (Float(y) - 64) * 2 / 120
            let d = sqrt(dx * dx + dy * dy)
            let a: Float = d < 0.62 ? 0.88 - (0.88 - 0.55) * (d / 0.62) : max(0, 0.55 * (1 - (d - 0.62) / 0.38))
            return (3.0 / 255, 6.0 / 255, 14.0 / 255, a)
        }
        // 6 crystal（六角冰晶：六臂＋0.45/0.72 分叉＋中心点＋径向晕）
        let crystal = makeTexture(w: 128, h: 128, srgb: false) { x, y in
            let px = (Float(x) - 64) / 64, py = (Float(y) - 64) / 64
            func segDist(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
                let abx = bx - ax, aby = by - ay
                let t = min(max(((px - ax) * abx + (py - ay) * aby) / max(abx * abx + aby * aby, 0.0001), 0), 1)
                let dx = px - (ax + abx * t), dy = py - (ay + aby * t)
                return sqrt(dx * dx + dy * dy)
            }
            var dmin: Float = 1e9
            for k in 0..<6 {
                let a = Float(k) * Float.pi / 3
                let dx = cos(a), dy = sin(a)
                dmin = min(dmin, segDist(0, 0, dx * 0.95, dy * 0.95))
                for f in [Float(0.45), Float(0.72)] {
                    let bx = dx * f, by = dy * f
                    let bl = 0.30 * (1 - f * 0.5)
                    for sgn in [Float(-1), 1] {
                        let ba = a + sgn * 0.6
                        dmin = min(dmin, segDist(bx, by, bx + cos(ba) * bl, by + sin(ba) * bl))
                    }
                }
            }
            let r = sqrt(px * px + py * py)
            var a = max(0, 1.15 - dmin * 26) * (1 - r * 0.35)
            if r < 0.09 { a = max(a, 0.95) }
            a = max(a, exp(-r * r * 4.5) * 0.22)
            return (1, 1, 1, min(a, 1))
        }
        textures = [soft, star, shadow, poolC, poolW, shade, crystal]
        texWhite = soft
    }

    private func textureFromCGImage(_ img: CGImage) -> MTLTexture? {
        guard let device else { return nil }
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                                                         width: w, height: h, mipmapped: false)
        d.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        bytes.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: w * 4)
        }
        return tex
    }

    // MARK: 装配（mount 时一次）

    func assemble() {
        guard !ready, let device else { return }
        guard let scene = XmasBake103.build() else {
            Breadcrumbs.log("p105 xmas bake=nil")
            return
        }
        baked = scene
        for img in scene.glbTextures { textures.append(textureFromCGImage(img)) }
        func buf(_ floats: [Float]) -> MTLBuffer? {
            floats.withUnsafeBytes { raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
            }
        }
        entPos = buf(scene.positions)
        entNrm = buf(scene.normals)
        entUV = buf(scene.uvs)
        entCol = buf(scene.colors)
        entIdx = scene.indices.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        var rng = XmasRNG103(seed: 20261225)
        func poolBuf(_ data: XmasPoolData103) -> PoolGPU {
            var g = PoolGPU()
            g.pos = buf(data.positions)
            g.col = buf(data.colors)
            g.misc1 = buf(data.misc1)
            g.dir = buf(data.dirs)
            g.count = data.count
            g.opacity = data.opacity
            g.snowMode = data.snowMode
            return g
        }
        poolOrbit = poolBuf(XmasTreeGen103.orbitPool(rng: rng))
        poolTrunk = poolBuf(XmasTreeGen103.trunkPool(rng: rng))
        poolCanopy = poolBuf(XmasTreeGen103.canopyPool(lampTops: scene.lampTops, rng: rng))
        poolSparkle = poolBuf(XmasTreeGen103.sparklePool(rng: rng))
        poolSky = poolBuf(XmasTreeGen103.skyPool(rng: rng))
        poolFarSnow = poolBuf(XmasTreeGen103.farSnowPool(rng: rng))
        lyrBuf = device.makeBuffer(length: XmasLyricMachine103.poolCount * 3 * 4, options: .storageModeShared)
        misc2Buf = device.makeBuffer(length: XmasLyricMachine103.poolCount * 3 * 4, options: .storageModeShared)
        misc2Zero = device.makeBuffer(length: XmasLyricMachine103.poolCount * 3 * 4, options: .storageModeShared)
        if let z = misc2Zero { memset(z.contents(), 0, z.length) }

        let sim = XmasSnowSim103(flats: scene.flats, benches: scene.benches)
        snowSim = sim
        fallPosBuf = device.makeBuffer(length: XmasSnowSim103.fallN * 3 * 4, options: .storageModeShared)
        fallMiscBuf = device.makeBuffer(length: XmasSnowSim103.fallN * 3 * 4, options: .storageModeShared)
        accPosBuf = device.makeBuffer(length: XmasSnowSim103.accN * 3 * 4, options: .storageModeShared)
        accMiscBuf = device.makeBuffer(length: XmasSnowSim103.accN * 3 * 4, options: .storageModeShared)
        accLifeBuf = device.makeBuffer(length: XmasSnowSim103.accN * 4, options: .storageModeShared)
        uploadAccum(pos: sim.accPositions, misc: sim.accMisc, life: sim.accLife)
        // (105) 首帧前同步跑一步模拟灌快照（此后模拟全在后台队列），
        // 免首帧雪片堆在原点。
        sim.update(dt: 1.0 / 60.0, now: 0)
        snapFallPos = sim.fallPositions; snapFallMisc = sim.fallMisc; snapFallDirty = true
        snapAccPos = sim.accPositions; snapAccMisc = sim.accMisc; snapAccLife = sim.accLife
        snapAccDirty = true
        sim.accDirty = false
        ready = true
        let texBytes = textures.compactMap { $0 }.reduce(0) { $0 + $1.width * $1.height * 4 }
        Breadcrumbs.log("p105 xmas bake tris=\(scene.triangleCount) verts=\(scene.vertexCount)"
            + " groups=\(scene.groups.count) pools orbit=\(poolOrbit.count) canopy=\(poolCanopy.count)"
            + " texMB=\(String(format: "%.1f", Double(texBytes) / 1_000_000))")
        // (105) GPU buffer 建好后释放 Swift 侧烘焙大数组（顶点/法线/
        // UV/颜色/索引＋GLB 原图，约 19MB）：baked 只留组参数、盘、
        // 光晕、落点等元数据供逐帧绘制与面包屑，驻留压回线内。
        baked?.positions = []
        baked?.normals = []
        baked?.uvs = []
        baked?.colors = []
        baked?.indices = []
        baked?.glbTextures = []
    }

    private func uploadAccum(pos: [Float], misc: [Float], life: [Float]) {
        if let b = accPosBuf { pos.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
        if let b = accMiscBuf { misc.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
        if let b = accLifeBuf { life.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
    }

    func teardown() {
        active = false
        ready = false
        baked = nil
        entPos = nil; entNrm = nil; entUV = nil; entCol = nil; entIdx = nil
        poolOrbit = PoolGPU(); poolTrunk = PoolGPU(); poolCanopy = PoolGPU()
        poolSparkle = PoolGPU(); poolSky = PoolGPU(); poolFarSnow = PoolGPU()
        lyrBuf = nil; misc2Buf = nil; misc2Zero = nil
        snowSim = nil
        fallPosBuf = nil; fallMiscBuf = nil; accPosBuf = nil; accMiscBuf = nil; accLifeBuf = nil
        hdrRT = nil; depthRT = nil
        bloomTex = [[nil, nil], [nil, nil], [nil, nil]]
        rtSize = .zero
        // (105) 复位异步状态，重进时首帧面包屑与模拟派发重新起算。
        firstFrameLogged = false
        sampleInFlight = -1
        snapLock.lock()
        simBusy = false
        snapFallDirty = false
        snapAccDirty = false
        sampleFlightDone = true
        snapLock.unlock()
        // 程序贴图保留（小、跨装配复用）；GLB 贴图随 baked 释放
        textures = Array(textures.prefix(7))
        Breadcrumbs.log("p105 xmas off fp=\(Breadcrumbs.footprintMB97())")
    }

    // MARK: 宿主面

    func setSnapshot(lines newLines: [LyricLine], trackId newTrack: String?) {
        if newTrack != trackId {
            trackId = newTrack
            lyricMachine.reset()
        }
        lines = newLines
    }

    func setActive(_ on: Bool) {
        active = on
        if !on {
            lastTickWall = nil
            // (105) 离开舞台/不可见：停 tick 之外再释放 RT 与 bloom
            // 链（约 52MB），驻留不长期占线；回到舞台时 ensureRTs
            // 按当前 drawable 尺寸重建。烘焙缓冲与贴图保留（重进
            // 免再烘焙），全释放只在 unmount 的 teardown。
            if hdrRT != nil || depthRT != nil {
                hdrRT = nil
                depthRT = nil
                bloomTex = [[nil, nil], [nil, nil], [nil, nil]]
                Breadcrumbs.log("p105 xmas rt released fp=\(Breadcrumbs.footprintMB97())")
            }
        }
    }

    private func noteResize() {
        // 尺寸档（画幅）变化时按样板 defaultView 重置 rig 目标
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let aspect = Float(size.width / size.height)
        lyricMachine.setAspect(aspect)
        let tier = aspect < 0.8 ? 0 : (aspect < 1.3 ? 1 : 2)
        if tier != aspectTier {
            aspectTier = tier
            switch tier {
            case 0: rigTTheta = 0.411; rigTPhi = 1.556; rigTRadius = 24.5; fovDeg = 52
            case 1: rigTTheta = 0.488; rigTPhi = 1.543; rigTRadius = 21.5; fovDeg = 44
            default: rigTTheta = 0.567; rigTPhi = 1.516; rigTRadius = 22; fovDeg = 40
            }
            if time == 0 { rigTheta = rigTTheta; rigPhi = rigTPhi; rigRadius = rigTRadius }
            Breadcrumbs.log("p105 xmas tier=\(tier) aspect=\(String(format: "%.2f", aspect))")
        }
    }

    // MARK: 手势（统一分发：同一套手势喂相机＋雪触点，DS 对账）

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    private func touchNow() { lastTouch = time }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let loc = g.location(in: view)
        switch g.state {
        case .began:
            dragging = true
            followAllowed = false
            velTheta = 0; velPhi = 0
            lastPan = loc
            lastPanT = CACurrentMediaTime()
            touchNow()
        case .changed:
            touchNow()
            let dx = Float(loc.x - lastPan.x), dy = Float(loc.y - lastPan.y)
            let now = CACurrentMediaTime()
            let dt = max(0.001, now - lastPanT)
            lastPanT = now
            lastPan = loc
            if g.numberOfTouches >= 2 { return }   // 双指归 pinch
            rigTTheta -= dx * 0.0052
            rigTPhi = min(1.58, max(0.92, rigTPhi - dy * 0.0032))
            velTheta = -dx * 0.0052 / Float(dt) * 0.016
            velPhi = -dy * 0.0032 / Float(dt) * 0.016
            // 拖动搅雪（雪层专属附加响应，样板同构）；(105) 写入
            // 派到 sim 队列，与后台模拟同线程改雪状态，免竞态。
            let spd = hypot(dx, dy)
            if spd > 2, let sim = snowSim {
                if let pt = rayPoint(loc, toCenter: SIMD3<Float>(0, 4.5, 0)) {
                    let power = min(1, spd * 0.05)
                    let tNow = time
                    simQueue.async {
                        sim.stirVel = SIMD3<Float>((pt.x - sim.stir.x) * 2.2, (pt.y - sim.stir.y) * 2.2, (pt.z - sim.stir.z) * 2.2)
                        sim.stir = pt
                        sim.stirPower = power
                        sim.stirT = tNow
                    }
                }
            }
        default:
            dragging = false
        }
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinching = true
            followAllowed = false
            lastPinchScale = 1
            touchNow()
        case .changed:
            touchNow()
            let dScale = Float(g.scale - lastPinchScale)
            lastPinchScale = g.scale
            let deltaPx = dScale * 300   // 尺度差→像素差近似（样板为双指距像素差）
            if abs(deltaPx) > 0.4 { spreadTarget = 0.6 }
            pinchSnowTarget = 1
            rigTRadius = min(26, max(8.5, rigTRadius - deltaPx * 0.03))
        default:
            pinching = false
            spreadTarget = 0
            pinchSnowTarget = 0
        }
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let loc = g.location(in: view)
        touchNow()
        guard let ray = rayDirection(loc) else { return }
        // ripple：先试树冠球（0,4.2,0) r 3.6，否则 z=0 平面回退（样板同式）
        var pt: SIMD3<Float>? = nil
        let center = SIMD3<Float>(0, 4.2, 0)
        let oc = camPos - center
        let b = simd_dot(oc, ray)
        let c = simd_dot(oc, oc) - 3.6 * 3.6
        let disc = b * b - c
        if disc >= 0 {
            let t = -b - sqrt(disc)
            if t > 0 { pt = camPos + ray * t }
        }
        if pt == nil {
            let tt = -camPos.z / ray.z
            if tt > 0 { pt = camPos + ray * tt }
        }
        if let p = pt, abs(p.x) < 6, p.y > -1, p.y < 11 {
            rippleStart = time
            ripplePos = p
        }
        // 同一次点按踢起雪沫（样板：以画面中心深度点为锚）；
        // (105) 派到 sim 队列执行（puff 逐片改速度，与模拟同线程）。
        if let sim = snowSim, let ppt = rayPoint(loc, toCenter: SIMD3<Float>(0, 4.5, 0)) {
            let py = min(9, max(0.5, ppt.y))
            simQueue.async { sim.puff(ppt.x, py, ppt.z) }
        }
    }

    private func rayDirection(_ loc: CGPoint) -> SIMD3<Float>? {
        let w = Float(view.bounds.width), h = Float(view.bounds.height)
        guard w > 0, h > 0 else { return nil }
        let ndcX = (Float(loc.x) / w) * 2 - 1
        let ndcY = 1 - (Float(loc.y) / h) * 2
        // 相机基（与 applyCamera 的 lookAt 同构）
        let fwd = simd_normalize(lookTarget - camPos)
        var right = simd_normalize(simd_cross(fwd, SIMD3<Float>(0, 1, 0)))
        if simd_length(right) < 0.001 { right = SIMD3<Float>(1, 0, 0) }
        let up = simd_cross(right, fwd)
        let tanY = tan(fovDeg * 0.5 * Float.pi / 180)
        let aspect = w / h
        return simd_normalize(fwd + right * (ndcX * tanY * aspect) + up * (ndcY * tanY))
    }

    private func rayPoint(_ loc: CGPoint, toCenter c: SIMD3<Float>) -> SIMD3<Float>? {
        guard let dir = rayDirection(loc) else { return nil }
        let t = max(2, simd_dot(dir, c - camPos))
        return camPos + dir * t
    }
}

// MARK: - 相机（applyCamera 逐式移植）＋逐帧更新＋渲染

extension XmasMetalEngine103 {

    private func applyCamera(dt: Float, lyricFrame: XmasLyricFrame103) {
        if !dragging && !pinching {
            rigTTheta += velTheta * dt * 60 * 0.016
            rigTPhi += velPhi * dt * 60 * 0.016
            velTheta *= pow(0.06, dt)
            velPhi *= pow(0.06, dt)
            rigTPhi = min(1.58, max(0.92, rigTPhi))
        }
        if !UIAccessibility.isReduceMotionEnabled, time - lastTouch > 4, !dragging, !pinching {
            rigTTheta += dt * 0.03
        }
        let k = 1 - pow(Float(0.0001), dt)
        rigTheta += (rigTTheta - rigTheta) * k
        rigPhi += (rigTPhi - rigPhi) * k
        rigRadius += (rigTRadius - rigRadius) * k

        if let a = lyricFrame.anchor, lyricFrame.justAssigned {
            var dTh = a.theta - rigTTheta
            dTh = atan2(sin(dTh), cos(dTh))
            followDTheta = dTh
            followPhi = a.phi
            followRadius = a.rRadius
            followFocus = SIMD3<Float>(a.pos.x, min(a.pos.y, 8.6), a.pos.z)
            followAllowed = true
        }
        followGoal = lyricFrame.followGoal
        let fGoal = (followAllowed && !dragging && !pinching) ? followGoal : 0
        let fBase: Float = fGoal > followCur ? 0.10 : 0.30
        followCur += (fGoal - followCur) * (1 - pow(fBase, dt))
        if followCur < 0.001 && fGoal == 0 { followCur = 0 }
        let fc = followCur
        let th = rigTheta + followDTheta * fc
        var ph = rigPhi + (followPhi - rigPhi) * fc
        ph = min(1.58, max(0.85, ph))
        let rad = rigRadius + (followRadius - rigRadius) * fc
        let target = camTarget + (followFocus - camTarget) * fc
        let sp = sin(ph)
        camPos = SIMD3<Float>(target.x + rad * sp * sin(th),
                              target.y + rad * cos(ph),
                              target.z + rad * sp * cos(th))
        lookTarget = target
        // view / proj
        let fwd = simd_normalize(target - camPos)
        var right = simd_normalize(simd_cross(fwd, SIMD3<Float>(0, 1, 0)))
        if simd_length(right) < 0.001 { right = SIMD3<Float>(1, 0, 0) }
        let up = simd_cross(right, fwd)
        var v = matrix_identity_float4x4
        v.columns.0 = SIMD4<Float>(right.x, up.x, -fwd.x, 0)
        v.columns.1 = SIMD4<Float>(right.y, up.y, -fwd.y, 0)
        v.columns.2 = SIMD4<Float>(right.z, up.z, -fwd.z, 0)
        v.columns.3 = SIMD4<Float>(-simd_dot(right, camPos), -simd_dot(up, camPos), simd_dot(fwd, camPos), 1)
        camView = v
        let aspect = max(Float(view.bounds.width) / max(Float(view.bounds.height), 1), 0.05)
        let ys = 1 / tan(fovDeg * 0.5 * Float.pi / 180)
        let xs = ys / aspect
        let zn: Float = 0.1, zf: Float = 160
        var p = simd_float4x4()
        p.columns.0 = SIMD4<Float>(xs, 0, 0, 0)
        p.columns.1 = SIMD4<Float>(0, ys, 0, 0)
        p.columns.2 = SIMD4<Float>(0, 0, zf / (zn - zf), -1)
        p.columns.3 = SIMD4<Float>(0, 0, zn * zf / (zn - zf), 0)
        camProj = p
    }

    /// 宿主逐帧入口：存 position、推进时钟、派发后台模拟/采样、
    /// 触发一帧绘制（绘制消费最近一份模拟快照）。
    func tick(position: TimeInterval) {
        latestPosition = position
        guard active, ready else { return }
        let now = CACurrentMediaTime()
        if let last = lastTickWall {
            let d = now - last
            if d > 0 && d < 0.5 { frameDt = Float(d); time += frameDt }
            noteFPS(d)
        }
        lastTickWall = now
        dispatchSimStep()
        dispatchSampleIfNeeded()
        view.draw()
    }

    /// 落雪模拟一步（后台队列）：算完把输出数组拷进快照槽，
    /// tick 线程的 render 只 memcpy 快照进 GPU buffer。
    private func dispatchSimStep() {
        guard let sim = snowSim else { return }
        snapLock.lock()
        if simBusy { snapLock.unlock(); return }
        simBusy = true
        snapLock.unlock()
        let dt = frameDt, now = time, pinch = pinchSnow
        simQueue.async { [weak self] in
            let t0 = CACurrentMediaTime()
            sim.pinchSnow = pinch
            sim.update(dt: dt, now: now)
            let ms = (CACurrentMediaTime() - t0) * 1000
            guard let self else { return }
            self.snapLock.lock()
            self.snapFallPos = sim.fallPositions
            self.snapFallMisc = sim.fallMisc
            self.snapFallDirty = true
            if sim.accDirty {
                self.snapAccPos = sim.accPositions
                self.snapAccMisc = sim.accMisc
                self.snapAccLife = sim.accLife
                self.snapAccDirty = true
                sim.accDirty = false
            }
            self.snapGust = sim.gust
            self.perfSimMax = max(self.perfSimMax, ms)
            self.simBusy = false
            self.snapLock.unlock()
        }
    }

    /// 字形采样派发（后台队列）：状态机登记请求后在此采样回填；
    /// 已备好/在飞则不重复派发，过期结果由状态机按行号自愈。
    private func dispatchSampleIfNeeded() {
        guard let req = lyricMachine.sampleRequest else {
            sampleInFlight = -1
            return
        }
        if lyricMachine.hasPrepared(line: req.line) {
            sampleInFlight = -1
            return
        }
        snapLock.lock()
        let flightDone = sampleFlightDone
        snapLock.unlock()
        if sampleInFlight == req.line && !flightDone { return }   // 采样中
        // 未派发，或上一发已回但结果被过期采样覆盖（备好槽对不上
        // 本行）→（重）派发，自愈。
        sampleInFlight = req.line
        snapLock.lock()
        sampleFlightDone = false
        snapLock.unlock()
        let machine = lyricMachine
        simQueue.async { [weak self] in
            let t0 = CACurrentMediaTime()
            let glyph = XmasGlyphSampler103.sample(
                text: req.text, scale: req.anchor.scale, aspect: req.aspect,
                rng: XmasRNG103(seed: UInt32(777000 + req.line * 131 + 7)))
            let ms = (CACurrentMediaTime() - t0) * 1000
            machine.provideGlyph(line: req.line, glyph: glyph)
            guard let self else { return }
            self.snapLock.lock()
            self.perfAssignMax = max(self.perfAssignMax, ms)
            self.sampleFlightDone = true
            self.snapLock.unlock()
        }
    }

    private func noteFPS(_ d: TimeInterval) {
        guard d > 0, d < 0.5 else { return }
        fpsAccum += d; fpsFrames += 1; fpsWindow += d
        if fpsWindow >= 5, fpsFrames > 0 {
            let avg = fpsAccum / Double(fpsFrames)
            // (105) 帧成本逐项打点：encAvg/encMax＝tick 线程编码
            // （毫秒），simMax＝后台落雪模拟峰值，assignMax＝后台
            // 字形采样峰值——160ms 级卡顿须能按此三项归因。
            let encAvg = perfEncN > 0 ? perfEncSum / Double(perfEncN) : 0
            snapLock.lock()
            let sMax = perfSimMax, aMax = perfAssignMax
            perfSimMax = 0; perfAssignMax = 0
            snapLock.unlock()
            Breadcrumbs.log("p105 xmas fps=\(String(format: "%.1f", 1.0 / avg))"
                + " avgMs=\(String(format: "%.2f", avg * 1000))"
                + " encAvg=\(String(format: "%.2f", encAvg)) encMax=\(String(format: "%.2f", perfEncMax))"
                + " simMax=\(String(format: "%.2f", sMax)) assignMax=\(String(format: "%.2f", aMax))"
                + " fp=\(Breadcrumbs.footprintMB97())")
            fpsAccum = 0; fpsFrames = 0; fpsWindow = 0
            perfEncSum = 0; perfEncMax = 0; perfEncN = 0
        }
    }

    // RT 管理（尺寸变化：本帧重建——旧 RT 拉伸一帧的等价近似为
    // 直接换新；drawable 尺寸变化只发生在旋转/布局帧，宿主另有
    // (102) 旋转快照盖兜底，见交付报告偏差注）
    private func ensureRTs() -> Bool {
        guard let device else { return false }
        let ds = view.drawableSize
        guard ds.width > 0, ds.height > 0 else { return false }
        if ds == rtSize && hdrRT != nil { return true }
        rtSize = ds
        let w = Int(ds.width), h = Int(ds.height)
        func rt(_ w: Int, _ h: Int, _ fmt: MTLPixelFormat, _ usage: MTLTextureUsage) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: max(w, 1), height: max(h, 1), mipmapped: false)
            d.usage = usage
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        hdrRT = rt(w, h, .rgba16Float, [.renderTarget, .shaderRead])
        depthRT = rt(w, h, .depth32Float, [.renderTarget])
        var bytes = w * h * 8 + w * h * 4
        for lvl in 0..<3 {
            let div = [2, 4, 8][lvl]
            let lw = max(w / div, 1), lh = max(h / div, 1)
            bloomTex[lvl][0] = rt(lw, lh, .rgba16Float, [.renderTarget, .shaderRead])
            bloomTex[lvl][1] = rt(lw, lh, .rgba16Float, [.renderTarget, .shaderRead])
            bytes += lw * lh * 8 * 2
        }
        rtBytes = bytes
        Breadcrumbs.log("p105 xmas rt \(w)x\(h) bytes=\(bytes) MB=\(String(format: "%.1f", Double(bytes) / 1_000_000))")
        return hdrRT != nil && depthRT != nil
    }

    func render() {
        guard active, ready, let queue, let baked,
              pipeEntOpaque != nil, pipeFinal != nil else { return }
        let encT0 = CACurrentMediaTime()
        if inflight.wait(timeout: .now()) == .timedOut { return }   // in-flight 闸：忙时跳过
        guard ensureRTs(), let hdr = hdrRT, let depth = depthRT,
              let drawable = view.currentDrawable else {
            inflight.signal()
            return
        }
        guard let cmd = queue.makeCommandBuffer() else { inflight.signal(); return }
        let sem = inflight
        cmd.addCompletedHandler { _ in sem.signal() }

        // ---- 歌词状态机（position 驱动） ----
        let idx = LyricParser.currentIndex(in: lines, at: latestPosition) ?? -1
        let lf = lyricMachine.update(lines: lines, lineIndex: idx, position: latestPosition)
        if lyricMachine.borrowDirty {
            if let b = lyrBuf { lyricMachine.aLyr.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
            if let b = misc2Buf { lyricMachine.aMisc2.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
            lyricMachine.borrowDirty = false
        }
        if lf.justAssigned, let a = lf.anchor {
            if a.name != lastAnchorName {
                lastAnchorName = a.name
                Breadcrumbs.log("p105 xmas anchor=\(a.name) line=\(idx)")
            }
        }
        applyCamera(dt: frameDt, lyricFrame: lf)
        if lf.justAssigned {
            // (105) 构图自证：每次锚点切换落一条相机/场景界/三角面。
            logFrameCrumb(baked)
        }

        // ---- 雪模拟快照消费（(105)：模拟在 simQueue 后台跑，
        // 此处只把最近一份快照 memcpy 进 GPU buffer） ----
        pinchSnow += (pinchSnowTarget - pinchSnow) * (1 - pow(Float(0.02), frameDt))
        snapLock.lock()
        if snapFallDirty {
            if let b = fallPosBuf { snapFallPos.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
            if let b = fallMiscBuf { snapFallMisc.withUnsafeBytes { memcpy(b.contents(), $0.baseAddress!, min(b.length, $0.count)) } }
            snapFallDirty = false
        }
        let accSnap: ([Float], [Float], [Float])? = snapAccDirty ? (snapAccPos, snapAccMisc, snapAccLife) : nil
        snapAccDirty = false
        lastGust = snapGust
        snapLock.unlock()
        if let (ap, am, al) = accSnap { uploadAccum(pos: ap, misc: am, life: al) }

        // ---- spread 弹簧 ----
        spreadCur += (spreadTarget - spreadCur) * (1 - pow(Float(0.001), frameDt))
        if !pinching && spreadTarget > 0 && spreadCur > 0.4 { spreadTarget = 0 }

        let viewProj = camProj * camView
        var frameU = XmasFrameU103()
        frameU.viewProj = viewProj
        frameU.view = camView
        frameU.camPos = SIMD4<Float>(camPos, 0)
        frameU.time = time
        let lights = makeLights(lyricFrame: lf)
        let uPR = max(Float(view.drawableSize.width) / max(Float(view.bounds.width), 1), 1)

        // ================= 场景 pass =================
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = hdr
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.002, green: 0.004, blue: 0.010, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.texture = depth
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.clearDepth = 1.0
        rp.depthAttachment.storeAction = .dontCare
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rp) else { cmd.commit(); return }

        // 实体：不透明组 → 混合组
        if let pos = entPos, let nrm = entNrm, let uv = entUV, let col = entCol, let idxB = entIdx {
            enc.setVertexBuffer(pos, offset: 0, index: 0)
            enc.setVertexBuffer(nrm, offset: 0, index: 1)
            enc.setVertexBuffer(uv, offset: 0, index: 2)
            enc.setVertexBuffer(col, offset: 0, index: 3)
            enc.setVertexBytes(&frameU, length: MemoryLayout<XmasFrameU103>.stride, index: 4)
            var lightsVar = lights
            enc.setFragmentBytes(&lightsVar, length: MemoryLayout<XmasLightsU103>.stride, index: 1)
            enc.setFragmentBytes(&frameU, length: MemoryLayout<XmasFrameU103>.stride, index: 2)
            if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
            for pass in 0..<2 {
                enc.setRenderPipelineState(pass == 0 ? pipeEntOpaque! : pipeEntBlend!)
                enc.setDepthStencilState(pass == 0 ? depthOn : depthOff)
                for g in baked.groups where g.indexCount > 0 && (pass == 0) != g.params.blend {
                    var gu = XmasEntGroupU103()
                    gu.baseColor = g.params.baseColor
                    let inten = currentEmissiveIntensity(g.params)
                    gu.emissive = SIMD4<Float>(g.params.emissiveColor * inten, 0)
                    gu.roughMetal = SIMD2<Float>(g.params.roughness, g.params.metallic)
                    let texSlot = g.params.texSlot
                    gu.useTex = texSlot >= 0 ? 1 : 0
                    enc.setFragmentBytes(&gu, length: MemoryLayout<XmasEntGroupU103>.stride, index: 0)
                    if texSlot >= 0, textures.indices.contains(7 + texSlot), let t = textures[7 + texSlot] {
                        enc.setFragmentTexture(t, index: 0)
                    } else if let tw = texWhite {
                        enc.setFragmentTexture(tw, index: 0)
                    }
                    enc.drawIndexedPrimitives(type: .triangle, indexCount: g.indexCount,
                                              indexType: .uint32, indexBuffer: idxB,
                                              indexBufferOffset: g.indexStart * 4)
                }
            }
        }

        // 地面盘：阴影（normal）→ 暖池/树池（additive）
        drawDiscs(enc: enc, frame: frameU, baked: baked)

        // 歌词衬底＋暖晕（sprites：shade normal / glow additive）
        drawGlyphBackdrop(enc: enc, lyricFrame: lf, viewProj: viewProj)

        // 静态光晕 sprites（additive soft）
        if !baked.glows.isEmpty {
            let insts = baked.glows.map {
                XmasSprInst103(center: $0.center, size: SIMD2<Float>($0.scale, $0.scale),
                               color: SIMD4<Float>($0.color, $0.opacity))
            }
            drawSprites(enc: enc, insts: insts, tex: textures.indices.contains(0) ? textures[0] : nil,
                        pipe: pipeSprAdd, viewProj: viewProj)
        }
        // 月亮（soft、normal、opacity 0.16）
        drawSprites(enc: enc,
                    insts: [XmasSprInst103(center: SIMD3<Float>(13, 12.5, -18), size: SIMD2<Float>(4.4, 4.4),
                                           color: SIMD4<Float>(xmasSRGB(0xd6e4ff), 0.16))],
                    tex: textures.indices.contains(0) ? textures[0] : nil,
                    pipe: pipeSprNorm, viewProj: viewProj)

        // 共享池各系统（additive、depth test 开/write 关）
        drawPools(enc: enc, lyricFrame: lf, viewProj: viewProj, uPR: uPR)

        // 树顶星（sprite 脉动＋cue swell，additive star/soft）
        let starCue: Float = (lf.anchor?.cue == "star") ? lf.env : 0
        let starScale = 2.9 + 0.26 * sin(time * 1.6)
        let starOp = 0.82 + 0.18 * sin(time * 1.6)
        drawSprites(enc: enc,
                    insts: [XmasSprInst103(center: SIMD3<Float>(0, 9.05, 0), size: SIMD2<Float>(starScale, starScale),
                                           color: SIMD4<Float>(1, 1, 1, starOp))],
                    tex: textures.indices.contains(1) ? textures[1] : nil,
                    pipe: pipeSprAdd, viewProj: viewProj)
        let glowScale = 5.6 * (1 + 0.18 * starCue)
        drawSprites(enc: enc,
                    insts: [XmasSprInst103(center: SIMD3<Float>(0, 9.05, 0), size: SIMD2<Float>(glowScale, glowScale),
                                           color: SIMD4<Float>(1.0, 0.8, 0.5, 0.85 * (1 + 0.55 * starCue)))],
                    tex: textures.indices.contains(0) ? textures[0] : nil,
                    pipe: pipeSprAdd, viewProj: viewProj)

        // 烟（normal soft，逐缕相位）
        drawSmoke(enc: enc, baked: baked, viewProj: viewProj)

        // 落雪＋积存（crystal、normal）
        drawSnow(enc: enc, viewProj: viewProj, uPR: uPR)

        enc.endEncoding()

        // ================= bloom 链 =================
        encodeBloom(cmd: cmd, src: hdr)

        // ================= 终程 =================
        let frp = MTLRenderPassDescriptor()
        frp.colorAttachments[0].texture = drawable.texture
        frp.colorAttachments[0].loadAction = .dontCare
        frp.colorAttachments[0].storeAction = .store
        if let fenc = cmd.makeRenderCommandEncoder(descriptor: frp) {
            fenc.setRenderPipelineState(pipeFinal!)
            fenc.setFragmentTexture(hdr, index: 0)
            fenc.setFragmentTexture(bloomTex[0][0], index: 1)
            fenc.setFragmentTexture(bloomTex[1][0], index: 2)
            fenc.setFragmentTexture(bloomTex[2][0], index: 3)
            if let sampler { fenc.setFragmentSamplerState(sampler, index: 0) }
            var fu = XmasFinalU103()
            fenc.setFragmentBytes(&fu, length: MemoryLayout<XmasFinalU103>.stride, index: 0)
            fenc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            fenc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
        if !firstFrameLogged {
            firstFrameLogged = true
            // (105) 首帧构图自证（相机位/场景界/三角面数）。
            logFrameCrumb(baked)
            Breadcrumbs.log("p105 xmas first frame rt=\(rtBytes) fp=\(Breadcrumbs.footprintMB97())")
        }
        let encMs = (CACurrentMediaTime() - encT0) * 1000
        perfEncSum += encMs; perfEncMax = max(perfEncMax, encMs); perfEncN += 1
    }

    /// (105) 构图自证面包屑：相机世界位＋烘焙场景包围盒＋三角面数。
    private func logFrameCrumb(_ baked: XmasBakedScene103) {
        func f(_ v: Float) -> String { String(format: "%.1f", v) }
        Breadcrumbs.log("p105 xmas frame cam=(\(f(camPos.x)),\(f(camPos.y)),\(f(camPos.z)))"
            + " bounds=(\(f(baked.boundsMin.x)),\(f(baked.boundsMin.y)),\(f(baked.boundsMin.z)))"
            + "-(\(f(baked.boundsMax.x)),\(f(baked.boundsMax.y)),\(f(baked.boundsMax.z)))"
            + " tris=\(baked.triangleCount)")
    }

    // MARK: 帧内子绘制

    private func currentEmissiveIntensity(_ p: XmasMatParams103) -> Float {
        var inten = p.emissiveIntensity
        if p.breathSp > 0 {
            inten *= 1 + 0.05 * sin(time * p.breathSp + p.breathPh)
        }
        return inten
    }

    private func makeLights(lyricFrame lf: XmasLyricFrame103) -> XmasLightsU103 {
        guard let baked else { return XmasLightsU103() }
        var L = XmasLightsU103()
        L.hemiSky = SIMD4<Float>(xmasSRGB(0x2c3a5c) * 0.34, 0)
        L.hemiGround = SIMD4<Float>(xmasSRGB(0x1c120a) * 0.34, 0)
        L.moonDir = SIMD4<Float>(simd_normalize(SIMD3<Float>(-16, 22, -8)), 0)
        L.moonColor = SIMD4<Float>(xmasSRGB(0xc9d9f2) * 0.24, 0)
        L.rimDir = SIMD4<Float>(simd_normalize(SIMD3<Float>(14, 9, 16)), 0)
        L.rimColor = SIMD4<Float>(xmasSRGB(0xffab5e) * 0.16, 0)
        // 点光槽：0 树心、1/2 门廊、3/4 路灯 dyn
        var pos: [SIMD4<Float>] = [SIMD4<Float>(0, 4.6, 0, 44),
                                   SIMD4<Float>(0, -100, 0, 0.001), SIMD4<Float>(0, -100, 0, 0.001),
                                   SIMD4<Float>(0, -100, 0, 0.001), SIMD4<Float>(0, -100, 0, 0.001)]
        var col: [SIMD4<Float>] = [SIMD4<Float>(xmasSRGB(0xffa64d) * 40, 0),
                                   SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0),
                                   SIMD4<Float>(0, 0, 0, 0), SIMD4<Float>(0, 0, 0, 0)]
        for (i, p) in baked.porchPos.enumerated() where i < 2 {
            pos[1 + i] = SIMD4<Float>(p, 10)
            col[1 + i] = SIMD4<Float>(xmasSRGB(0xffa64d) * 10, 0)
        }
        // lamp cue：最近 dyn 路灯应和（样板 dynLights 口径）
        var cueIdx = -1
        if lf.anchor?.cue == "lamp", lf.env > 0.02, let a = lf.anchor {
            var bd: Float = 1e18
            for (i, p) in baked.lampDynPos.enumerated() {
                let d = simd_distance_squared(SIMD2<Float>(p.x, p.z), SIMD2<Float>(a.pos.x, a.pos.z))
                if d < bd { bd = d; cueIdx = i }
            }
        }
        for (i, p) in baked.lampDynPos.enumerated() where i < 2 {
            let ph = baked.lampDynPh[i]
            var inten: Float = 14 * (1 + 0.05 * sin(time * 13.7 + ph) * sin(time * 3.1 + ph) + 0.03 * sin(time * 1.3 + ph))
            if i == cueIdx { inten *= 1 + 0.45 * lf.env * (0.75 + 0.25 * sin(time * 7 + ph)) }
            pos[3 + i] = SIMD4<Float>(p, 13)
            col[3 + i] = SIMD4<Float>(xmasSRGB(0xffb45c) * inten, 0)
        }
        L.ptPos = (pos[0], pos[1], pos[2], pos[3], pos[4])
        L.ptColor = (col[0], col[1], col[2], col[3], col[4])
        return L
    }

    private func drawDiscs(enc: MTLRenderCommandEncoder, frame: XmasFrameU103, baked: XmasBakedScene103) {
        var sprU = XmasSprU103()
        sprU.viewProj = frame.viewProj
        sprU.view = frame.view
        let shadows = baked.discs.filter { $0.kind == .shadow }
        let pools = baked.discs.filter { $0.kind != .shadow }
        if !shadows.isEmpty, let pipe = pipeDiscShadow, let tex = textures.indices.contains(2) ? textures[2] : nil {
            var insts = shadows.map { XmasDiscInst103(center: $0.center, size: $0.size, rotY: $0.rotY, color: $0.color) }
            enc.setRenderPipelineState(pipe)
            enc.setDepthStencilState(depthOff)
            enc.setVertexBytes(&sprU, length: MemoryLayout<XmasSprU103>.stride, index: 1)
            enc.setFragmentTexture(tex, index: 0)
            if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
            insts.withUnsafeBytes { raw in
                enc.setVertexBuffer(device?.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared),
                                    offset: 0, index: 0)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: insts.count)
        }
        if !pools.isEmpty, let pipe = pipeDiscAdd {
            var insts: [XmasDiscInst103] = pools.map {
                var c = $0.color
                if $0.kind == .treePool { c.w = 0.85 + 0.15 * sin(time * 0.9) }
                return XmasDiscInst103(center: $0.center, size: $0.size, rotY: $0.rotY, color: c)
            }
            enc.setRenderPipelineState(pipe)
            enc.setDepthStencilState(depthOff)
            enc.setVertexBytes(&sprU, length: MemoryLayout<XmasSprU103>.stride, index: 1)
            let tex = textures.indices.contains(3) ? textures[3] : nil
            enc.setFragmentTexture(tex, index: 0)
            if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
            insts.withUnsafeBytes { raw in
                enc.setVertexBuffer(device?.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared),
                                    offset: 0, index: 0)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: insts.count)
        }
    }

    private func drawSprites(enc: MTLRenderCommandEncoder, insts: [XmasSprInst103], tex: MTLTexture?,
                             pipe: MTLRenderPipelineState?, viewProj: simd_float4x4) {
        guard !insts.isEmpty, let pipe, let tex, let device else { return }
        var sprU = XmasSprU103()
        sprU.viewProj = viewProj
        sprU.view = camView
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthOff)
        enc.setVertexBytes(&sprU, length: MemoryLayout<XmasSprU103>.stride, index: 1)
        enc.setFragmentTexture(tex, index: 0)
        if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
        var arr = insts
        arr.withUnsafeBytes { raw in
            if let b = device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared) {
                enc.setVertexBuffer(b, offset: 0, index: 0)
            }
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: arr.count)
    }

    private func drawGlyphBackdrop(enc: MTLRenderCommandEncoder, lyricFrame lf: XmasLyricFrame103,
                                   viewProj: simd_float4x4) {
        guard let a = lf.anchor, lf.shade > 0.003 else { return }
        drawSprites(enc: enc,
                    insts: [XmasSprInst103(center: a.pos, size: SIMD2<Float>(lf.glyphW * 1.24, lf.glyphH * 2.7),
                                           color: SIMD4<Float>(1, 1, 1, lf.shade))],
                    tex: textures.indices.contains(5) ? textures[5] : nil,
                    pipe: pipeSprNorm, viewProj: viewProj)
        drawSprites(enc: enc,
                    insts: [XmasSprInst103(center: a.pos, size: SIMD2<Float>(lf.glyphW * 1.4, lf.glyphH * 3.4),
                                           color: SIMD4<Float>(xmasSRGB(0xffca7a), lf.shade * 0.32))],
                    tex: textures.indices.contains(0) ? textures[0] : nil,
                    pipe: pipeSprAdd, viewProj: viewProj)
    }

    private func drawSmoke(enc: MTLRenderCommandEncoder, baked: XmasBakedScene103, viewProj: simd_float4x4) {
        var insts: [XmasSprInst103] = []
        for anchor in baked.smokeAnchors {
            for i in 0..<5 {
                let ph = Float(i) / 5 + Float((i * 37 + Int(anchor.x * 10)) % 10) * 0.008
                let sph = (time * 0.09 + ph).truncatingRemainder(dividingBy: 1)
                let y = anchor.y + sph * 2.3
                let x = anchor.x + sph * sph * 1.1 + sin(time * 0.5 + ph * 9.0) * 0.08
                let sc = 0.5 + sph * 1.5
                let op = sin(sph * Float.pi) * 0.16
                insts.append(XmasSprInst103(center: SIMD3<Float>(x, y, anchor.z),
                                            size: SIMD2<Float>(sc, sc),
                                            color: SIMD4<Float>(xmasSRGB(0x93a9c6), op)))
            }
        }
        drawSprites(enc: enc, insts: insts, tex: textures.indices.contains(0) ? textures[0] : nil,
                    pipe: pipeSprNorm, viewProj: viewProj)
    }

    private func drawPools(enc: MTLRenderCommandEncoder, lyricFrame lf: XmasLyricFrame103,
                           viewProj: simd_float4x4, uPR: Float) {
        guard let pipe = pipePool else { return }
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthOff)
        if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
        let rt = time - rippleStart
        let gustVal: Float = lastGust * 0.85 + pinchSnow * 0.7
        func drawOne(_ g: PoolGPU, isOrbit: Bool, isFarSnow: Bool) {
            guard g.count > 0, let pos = g.pos, let col = g.col, let m1 = g.misc1, let dir = g.dir else { return }
            var U = XmasPoolU103()
            U.viewProj = viewProj
            U.view = camView
            U.uTime = time
            U.uPR = uPR
            U.uSnow = g.snowMode ? 1 : 0
            U.uOpacity = g.opacity
            if isOrbit {
                U.uSpread = spreadCur * 1.7
                U.uRippleT = (rt >= 0 && rt < 2.2) ? rt : -1
                U.uRipplePos = SIMD4<Float>(ripplePos, 0)
                U.uFly = lf.fly
                U.uReturn = lf.ret
                U.uCharLit = lf.charLit
                U.uBreath = lf.breath
                if let a = lf.anchor {
                    U.uLyrPos = SIMD4<Float>(a.pos, 0)
                    let yaw = atan2(camPos.x - a.pos.x, camPos.z - a.pos.z)
                    U.uLyrCos = cos(yaw)
                    U.uLyrSin = sin(yaw)
                    let wd = simd_normalize(a.wind)
                    U.uWindDir = SIMD4<Float>(wd, 0)
                    U.uWindAmt = a.windAmt
                    U.uRibbonAmp = a.ribbonAmp
                }
            }
            if isFarSnow { U.uGust = gustVal }
            enc.setVertexBuffer(pos, offset: 0, index: 0)
            enc.setVertexBuffer(col, offset: 0, index: 1)
            enc.setVertexBuffer(m1, offset: 0, index: 2)
            enc.setVertexBuffer(dir, offset: 0, index: 3)
            enc.setVertexBuffer(lyrBuf, offset: 0, index: 4)
            enc.setVertexBuffer(isOrbit ? misc2Buf : misc2Zero, offset: 0, index: 5)
            enc.setVertexBytes(&U, length: MemoryLayout<XmasPoolU103>.stride, index: 6)
            enc.setFragmentBytes(&U, length: MemoryLayout<XmasPoolU103>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: g.count)
        }
        drawOne(poolSparkle, isOrbit: false, isFarSnow: false)
        drawOne(poolSky, isOrbit: false, isFarSnow: false)
        drawOne(poolCanopy, isOrbit: false, isFarSnow: false)
        drawOne(poolTrunk, isOrbit: false, isFarSnow: false)
        drawOne(poolOrbit, isOrbit: true, isFarSnow: false)
        drawOne(poolFarSnow, isOrbit: false, isFarSnow: true)
    }

    private func drawSnow(enc: MTLRenderCommandEncoder, viewProj: simd_float4x4, uPR: Float) {
        guard let pipe = pipeSnow, let tex = textures.indices.contains(6) ? textures[6] : nil else { return }
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depthOff)
        enc.setFragmentTexture(tex, index: 0)
        if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
        var U = XmasSnowU103()
        U.viewProj = viewProj
        U.view = camView
        U.camPos = SIMD4<Float>(camPos, 0)
        U.uTime = time
        U.uPR = uPR
        // 落雪（mode 0）
        if let fp = fallPosBuf, let fm = fallMiscBuf, let zero = misc2Zero {
            U.uMode = 0
            U.uOpacity = 0.95
            enc.setVertexBuffer(fp, offset: 0, index: 0)
            enc.setVertexBuffer(fm, offset: 0, index: 1)
            enc.setVertexBuffer(zero, offset: 0, index: 2)   // aLife 未用（mode 0）
            enc.setVertexBytes(&U, length: MemoryLayout<XmasSnowU103>.stride, index: 3)
            enc.setFragmentBytes(&U, length: MemoryLayout<XmasSnowU103>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: XmasSnowSim103.fallN)
        }
        // 积存（mode 1）
        if let ap = accPosBuf, let am = accMiscBuf, let al = accLifeBuf {
            U.uMode = 1
            U.uOpacity = 1
            enc.setVertexBuffer(ap, offset: 0, index: 0)
            enc.setVertexBuffer(am, offset: 0, index: 1)
            enc.setVertexBuffer(al, offset: 0, index: 2)
            enc.setVertexBytes(&U, length: MemoryLayout<XmasSnowU103>.stride, index: 3)
            enc.setFragmentBytes(&U, length: MemoryLayout<XmasSnowU103>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: XmasSnowSim103.accN)
        }
    }

    private func encodeBloom(cmd: MTLCommandBuffer, src: MTLTexture) {
        guard let pipeBright, let pipeBlur, let pipeDown else { return }
        func pass(_ tex: MTLTexture?, _ pipe: MTLRenderPipelineState, _ setup: (MTLRenderCommandEncoder) -> Void) {
            guard let tex else { return }
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = tex
            rp.colorAttachments[0].loadAction = .dontCare
            rp.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rp) else { return }
            enc.setRenderPipelineState(pipe)
            if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
            setup(enc)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        var B = XmasBloomU103()
        // 亮通 → L0[1]
        pass(bloomTex[0][1], pipeBright) { enc in
            enc.setFragmentTexture(src, index: 0)
            B.texel = SIMD2<Float>(1 / Float(src.width), 1 / Float(src.height))
            enc.setFragmentBytes(&B, length: MemoryLayout<XmasBloomU103>.stride, index: 0)
        }
        // 每级：H/V 模糊（pingpong 结束回 [0]）＋向下采样到下一级 [1] 作模糊输入
        for lvl in 0..<3 {
            let texA = bloomTex[lvl][0]
            let texB = bloomTex[lvl][1]
            guard let tA = texA, let tB = texB else { continue }
            // 先把 [1] 模糊到 [0]（输入 [1] → H → 临时用 [0]？顺序：B 含源，先 H: B→A, V: A→B, H: B→A 收尾回 A）
            pass(tA, pipeBlur) { enc in
                enc.setFragmentTexture(tB, index: 0)
                B.texel = SIMD2<Float>(1 / Float(tB.width), 1 / Float(tB.height))
                B.dir = SIMD2<Float>(1, 0)
                enc.setFragmentBytes(&B, length: MemoryLayout<XmasBloomU103>.stride, index: 0)
            }
            pass(tB, pipeBlur) { enc in
                enc.setFragmentTexture(tA, index: 0)
                B.texel = SIMD2<Float>(1 / Float(tA.width), 1 / Float(tA.height))
                B.dir = SIMD2<Float>(0, 1)
                enc.setFragmentBytes(&B, length: MemoryLayout<XmasBloomU103>.stride, index: 0)
            }
            pass(tA, pipeBlur) { enc in
                enc.setFragmentTexture(tB, index: 0)
                B.texel = SIMD2<Float>(1 / Float(tB.width), 1 / Float(tB.height))
                B.dir = SIMD2<Float>(1, 0)
                enc.setFragmentBytes(&B, length: MemoryLayout<XmasBloomU103>.stride, index: 0)
            }
            if lvl < 2, let nextB = bloomTex[lvl + 1][1] {
                pass(nextB, pipeDown) { enc in
                    enc.setFragmentTexture(tA, index: 0)
                    B.texel = SIMD2<Float>(1 / Float(tA.width), 1 / Float(tA.height))
                    B.weight = 1
                    enc.setFragmentBytes(&B, length: MemoryLayout<XmasBloomU103>.stride, index: 0)
                }
            }
        }
    }
}
