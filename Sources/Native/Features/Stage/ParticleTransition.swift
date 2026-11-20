import UIKit
import Metal
import MetalKit
import QuartzCore

// 粒子成字/散字换行仪式层（3.7 (49)，借鉴 React Bits
// ParticleText / design-lab 的行级 morph 概念与参数，只借
// 概念与参数思路、实现自研）：
//  - 翻行时把旧行/新行的真实渲染（含姿态、颜色）快照采样
//    成点阵，旧行粒子散开、新行粒子聚拢成字，末段与真实
//    行交叉淡入衔接。粒子只管过渡：触发在行完成/翻行事
//    件之后，不反向影响字亮阈值与扫光时间轴。
//  - 渲染走 Metal 点精灵实例化：粒子池在每次 begin 时一
//    次性灌入实例缓冲（上限两行各 1600），逐帧零 CPU 更
//    新（位置/透明全在顶点着色器按时间纯函数求值），不
//    每词/每行新建纹理。绘制由宿主 frameTick 以
//    setNeedsDisplay 按需驱动，不自建时钟推歌词时间。
//  - Metal 不可用（模拟器异常等）时 isAvailable=false，
//    宿主静默跳过本层、走原出入场。

/// 一行歌词的采样点阵（宿主视图坐标系）。
struct ParticleField {
    var points: [(point: CGPoint, color: UIColor)]
}

enum ParticleFieldSampler {

    /// 把任意行视图的当前图层树渲染成图并采样不透明像素。
    /// scale=2 的采样分辨率对点精灵足够（粒子本身 2–4pt）。
    static func sample(view: UIView, in host: UIView,
                       maxPoints: Int) -> ParticleField? {
        let bounds = view.bounds
        guard bounds.width > 8, bounds.height > 8 else { return nil }
        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 自适应步长：先粗数一遍不透明像素，再定步长把总
        // 点数压进 maxPoints（行采样 ≈1.4k 与样片同量级）。
        func collect(step: Int) -> [(point: CGPoint, color: UIColor)] {
            var out: [(point: CGPoint, color: UIColor)] = []
            out.reserveCapacity(maxPoints)
            var py = step / 2
            while py < height {
                var px = step / 2
                while px < width {
                    let i = (py * width + px) * 4
                    let a = pixels[i + 3]
                    if a >= 110 {
                        let inv = 255 / CGFloat(max(a, 1))
                        let color = UIColor(
                            red: min(CGFloat(pixels[i]) * inv / 255, 1),
                            green: min(CGFloat(pixels[i + 1]) * inv / 255, 1),
                            blue: min(CGFloat(pixels[i + 2]) * inv / 255, 1),
                            alpha: CGFloat(a) / 255)
                        let viewPoint = CGPoint(x: CGFloat(px) / scale,
                                                y: CGFloat(py) / scale)
                        out.append((view.convert(viewPoint, to: host), color))
                    }
                    px += step
                }
                py += step
            }
            return out
        }
        var step = 3
        var points = collect(step: step)
        while points.count > maxPoints && step < 30 {
            step += 2
            points = collect(step: step)
        }
        guard points.count >= 12 else { return nil }
        return ParticleField(points: points)
    }
}

/// Metal 点精灵粒子层。宿主职责：翻行时调 begin、每帧
/// 调 tick、切歌/卸载时调 cancel。
final class ParticleTransitionView: MTKView {

    // 与着色器 struct 逐字对齐的实例布局。
    private struct Particle {
        var src: SIMD2<Float>
        var dst: SIMD2<Float>
        var srcColor: SIMD4<Float>
        var dstColor: SIMD4<Float>
        var delay: Float
        var duration: Float
        var seed: Float
        var size: Float
        var kind: Float   // 0 = 散开（旧行），1 = 聚拢（新行）
        var arc: Float
    }

    private struct Uniforms {
        var elapsed: Float
        var masterAlpha: Float
        var viewport: SIMD2<Float>
        var pointScale: Float
        var pad: Float = 0
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Particle {
        float2 src; float2 dst; float4 srcColor; float4 dstColor;
        float delay; float duration; float seed; float size;
        float kind; float arc;
    };
    struct Uniforms {
        float elapsed; float masterAlpha; float2 viewport;
        float pointScale; float pad;
    };
    struct VOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float4 color;
    };
    vertex VOut particleVertex(uint instanceID [[instance_id]],
                               constant Particle *particles [[buffer(0)]],
                               constant Uniforms &u [[buffer(1)]]) {
        Particle p = particles[instanceID];
        float t = clamp((u.elapsed - p.delay) / max(p.duration, 0.001), 0.0, 1.0);
        float2 pos;
        float alpha;
        float4 color;
        float shrink = 1.0;
        if (p.kind < 0.5) {
            float e = 1.0 - pow(1.0 - t, 3.0);
            pos = mix(p.src, p.dst, e);
            pos.y += sin(t * 3.14159) * p.arc;
            alpha = (1.0 - t) * step(0.0005, t);
            color = p.srcColor;
            shrink = 1.0 - 0.45 * t;
        } else {
            float e = t < 0.5 ? 4.0 * t * t * t
                              : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
            pos = mix(p.src, p.dst, e);
            pos.y += sin(t * 3.14159) * p.arc;
            alpha = smoothstep(0.0, 0.12, t);
            color = p.dstColor;
        }
        VOut out;
        out.position = float4((pos.x / u.viewport.x) * 2.0 - 1.0,
                              1.0 - (pos.y / u.viewport.y) * 2.0, 0.0, 1.0);
        out.pointSize = max(p.size * u.pointScale * shrink, 1.0);
        out.color = float4(color.rgb, color.a * alpha * u.masterAlpha);
        return out;
    }
    fragment float4 particleFragment(VOut in [[stage_in]],
                                     float2 pointCoord [[point_coord]]) {
        float d = length(pointCoord - 0.5) * 2.0;
        float a = smoothstep(1.0, 0.3, d);
        return float4(in.color.rgb, in.color.a * a);
    }
    """

    let isAvailable: Bool
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private var instanceBuffer: MTLBuffer?
    private var instanceCount = 0

    private var startTime: CFTimeInterval = 0
    private var totalDuration: TimeInterval = 0
    private var revealAt: TimeInterval = 0
    private var revealFired = false
    private(set) var isRunning = false

    /// elapsed 越过 reveal 点（真实新行该淡入的时刻）调一次。
    var onReveal: (() -> Void)?
    /// 过渡自然结束时调一次。
    var onFinish: (() -> Void)?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        var queue: MTLCommandQueue?
        var pipe: MTLRenderPipelineState?
        if let device {
            queue = device.makeCommandQueue()
            if let library = try? device.makeLibrary(source: Self.shaderSource,
                                                     options: nil),
               let vertex = library.makeFunction(name: "particleVertex"),
               let fragment = library.makeFunction(name: "particleFragment") {
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = vertex
                desc.fragmentFunction = fragment
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                desc.colorAttachments[0].isBlendingEnabled = true
                desc.colorAttachments[0].rgbBlendOperation = .add
                desc.colorAttachments[0].alphaBlendOperation = .add
                desc.colorAttachments[0].sourceRGBBlendFactor = .one
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipe = try? device.makeRenderPipelineState(descriptor: desc)
            }
        }
        self.commandQueue = queue
        self.pipeline = pipe
        self.isAvailable = device != nil && queue != nil && pipe != nil
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        enableSetNeedsDisplay = true
        isPaused = true
        isUserInteractionEnabled = false
        layer.isOpaque = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: 驱动（宿主 frameTick）

    /// 开始一次换行过渡。outgoing 旧行散开、incoming 新行
    /// 聚拢；reveal 在总时长 74% 处（宿主把真实新行淡入，
    /// 粒子同步 masterAlpha 压下衔接）。
    func begin(outgoing: ParticleField?, incoming: ParticleField?,
               duration: TimeInterval = 1.15) {
        guard isAvailable, let device else { return }
        var particles: [Particle] = []
        var rng = SystemRandomNumberGenerator()
        func rand(_ range: ClosedRange<Float>) -> Float {
            Float.random(in: range, using: &rng)
        }
        if let outgoing {
            for (index, item) in outgoing.points.enumerated() {
                // 散开方向：种子伪随机全向，略带上扬与重力
                // 漂移；约 22% 走大弧绕行（样片同口径）。
                let angle = rand(0...(2 * .pi))
                let big = index % 100 < 22
                let dist = big ? rand(90...170) : rand(28...95)
                let src = SIMD2<Float>(Float(item.point.x), Float(item.point.y))
                let dst = src + SIMD2<Float>(cos(angle) * dist,
                                             sin(angle) * dist * 0.7 + 16)
                let c = item.color.rgbaSIMD
                particles.append(Particle(
                    src: src, dst: dst, srcColor: c, dstColor: c,
                    delay: rand(0...0.18),
                    duration: Float(duration) * Float(rand(0.5...0.66)),
                    seed: rand(0...1), size: rand(2.4...4.6), kind: 0,
                    arc: big ? rand(-46...-14) : rand(-16...10)))
            }
        }
        if let incoming {
            for item in incoming.points {
                // 聚拢起点：目标点四周 40–150pt 漂移位，偏
                // 上方来向；逐粒子 stagger（样片 0–0.55s 的
                // 行级口径按总时长折算）。
                let angle = rand(0...(2 * .pi))
                let dist = rand(40...150)
                let dst = SIMD2<Float>(Float(item.point.x), Float(item.point.y))
                let src = dst + SIMD2<Float>(cos(angle) * dist,
                                             sin(angle) * dist * 0.6 - 26)
                let c = item.color.rgbaSIMD
                particles.append(Particle(
                    src: src, dst: dst, srcColor: c, dstColor: c,
                    delay: rand(0.04...0.34),
                    duration: Float(duration) * Float(rand(0.62...0.8)),
                    seed: rand(0...1), size: rand(2.4...4.6), kind: 1,
                    arc: rand(-26...-6)))
            }
        }
        guard !particles.isEmpty,
              let buffer = device.makeBuffer(
                bytes: particles,
                length: particles.count * MemoryLayout<Particle>.stride,
                options: .storageModeShared)
        else { return }
        instanceBuffer = buffer
        instanceCount = particles.count
        totalDuration = duration
        revealAt = duration * 0.74
        revealFired = false
        startTime = CACurrentMediaTime()
        isRunning = true
        setNeedsDisplay()
    }

    /// 宿主每帧调：推进 reveal/结束判定并请求重绘。
    func tick() {
        guard isRunning else { return }
        let elapsed = CACurrentMediaTime() - startTime
        if !revealFired && elapsed >= revealAt {
            revealFired = true
            onReveal?()
        }
        if elapsed >= totalDuration {
            isRunning = false
            instanceCount = 0
            instanceBuffer = nil
            setNeedsDisplay()
            onFinish?()
            return
        }
        setNeedsDisplay()
    }

    /// 立即中止（切歌/卸载/新翻行抢占）：清粒子，不回调。
    func cancel() {
        isRunning = false
        instanceCount = 0
        instanceBuffer = nil
        revealFired = true
        setNeedsDisplay()
    }

    // MARK: MTKView 绘制

    override func draw(_ rect: CGRect) {
        guard let pipeline, let commandQueue,
              let descriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let buffer = commandQueue.makeCommandBuffer()
        else { return }
        descriptor.colorAttachments[0].clearColor = clearColor
        descriptor.colorAttachments[0].loadAction = .clear
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        if isRunning, instanceCount > 0, let instanceBuffer,
           bounds.width > 0, bounds.height > 0 {
            let elapsed = Float(CACurrentMediaTime() - startTime)
            // masterAlpha：reveal 前恒 1，其后线性压到 0，
            // 与真实行 0.25s 淡入交叉衔接。
            var master: Float = 1
            if elapsed > Float(revealAt) {
                master = max(0, 1 - (elapsed - Float(revealAt))
                    / max(Float(totalDuration) - Float(revealAt), 0.01))
            }
            var uniforms = Uniforms(
                elapsed: elapsed, masterAlpha: master,
                viewport: SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
                pointScale: Float(window?.screen.scale ?? 2))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0,
                                   vertexCount: 1, instanceCount: instanceCount)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

private extension UIColor {
    var rgbaSIMD: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if !getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            getWhite(&white, alpha: &a)
            r = white; g = white; b = white
        }
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}
