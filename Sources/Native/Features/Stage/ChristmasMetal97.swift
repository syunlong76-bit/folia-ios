import MetalKit
import UIKit

// (97) 第 2 条：圣诞树 GPU 渲染层。旧实现逐帧在 UIView.draw
// 里以 CGContext 全量重画约 7100 粒×（多数两遍：晕＋芯），
// 每粒 saveGState/draw/restore，3x 位图 CPU 光栅化——稳态
// 2.7fps/单帧约 370ms 的成本全在这里。改：粒子位置/尺寸/
// alpha 仍由 ChristmasTreeStageRenderer 的既有数学逐帧算
// （口径不动），但只产出实例数组；绘制走 Metal 一次性批量
// 提交（精灵图集＋实例化四边形），合成在 GPU。渲染分辨率
// ＝drawable 原生尺寸（设备原生、不降清不封顶，沿 (94)
// 94-8 口径）；被去掉的是 CPU 的 3x 全量重画，不是分辨率。
// 填充形（远景剪影三角/树干梯形）走同管线固体色三角形路。

/// 精灵实例（点坐标，y 向下，与旧 draw 口径一致）。
/// 布局与着色器 SpriteIn97 逐字对齐：center/size 各 float2、
/// uv float4、alpha float，尾部 3 个保留 float 把 stride
/// 补到 48B（Metal 侧 float4 对齐后的结构体步长）。
struct XmasSpriteInstance97 {
    var cx: Float = 0, cy: Float = 0      // 中心（pt）
    var w: Float = 0, h: Float = 0        // 尺寸（pt）
    var u0: Float = 0, v0: Float = 0      // 图集 UV（左上）
    var u1: Float = 0, v1: Float = 0      // 图集 UV（右下）
    var alpha: Float = 0                  // 全局 alpha（旧 setAlpha）
    var _r0: Float = 0, _r1: Float = 0, _r2: Float = 0
}

/// 固体色三角形（填充形，渲染器侧的追加格式）。
struct XmasSolidTri97 {
    var x0: Float = 0, y0: Float = 0
    var x1: Float = 0, y1: Float = 0
    var x2: Float = 0, y2: Float = 0
    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
}

/// 三角形顶点（与着色器 TriIn97 对齐：float2＋16B 对齐
/// 填充＋float4，stride 32B）。
private struct XmasTriVert97 {
    var px: Float = 0, py: Float = 0
    var _p0: Float = 0, _p1: Float = 0
    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
}

private let xmasShaderSource97 = """
#include <metal_stdlib>
using namespace metal;
struct SpriteIn97 {
    float2 center; float2 size; float4 uv; float alpha;
};
struct VSOut97 {
    float4 pos [[position]];
    float2 uv;
    float alpha;
};
vertex VSOut97 vsSprite97(uint vid [[vertex_id]],
                          const device SpriteIn97* insts [[buffer(0)]],
                          constant float2& viewSize [[buffer(1)]]) {
    uint idx = vid / 6;
    uint corner = vid % 6;
    // 三角形对：(0,0)(1,0)(0,1) (0,1)(1,0)(1,1)
    float cx = (corner == 1 || corner == 4 || corner == 5) ? 1.0 : 0.0;
    float cy = (corner == 2 || corner == 3 || corner == 5) ? 1.0 : 0.0;
    SpriteIn97 s = insts[idx];
    float2 p = s.center + (float2(cx, cy) - 0.5) * s.size;
    VSOut97 o;
    o.pos = float4((p.x / viewSize.x) * 2.0 - 1.0,
                   1.0 - (p.y / viewSize.y) * 2.0, 0.0, 1.0);
    o.uv = float2(mix(s.uv.x, s.uv.z, cx), mix(s.uv.y, s.uv.w, cy));
    o.alpha = s.alpha;
    return o;
}
fragment float4 fsSprite97(VSOut97 in [[stage_in]],
                           texture2d<float> tex [[texture(0)]]) {
    constexpr sampler smp(mag_filter::linear, min_filter::linear);
    float4 c = tex.sample(smp, in.uv);
    // 图集位图为预乘 alpha（CG 位图上下文口径）：rgb 已乘 a，
    // 全局 alpha 须同乘 rgb 与 a，配合 .one/.oneMinusSrcAlpha
    // 混合即旧 CG source-over＋setAlpha 的等价式。
    float a = c.a * in.alpha;
    return float4(c.rgb * in.alpha, a);
}
struct TriIn97 {
    float2 p; float4 color;
};
struct TriOut97 {
    float4 pos [[position]];
    float4 color;
};
vertex TriOut97 vsTri97(uint vid [[vertex_id]],
                        const device TriIn97* verts [[buffer(0)]],
                        constant float2& viewSize [[buffer(1)]]) {
    TriIn97 v = verts[vid];
    TriOut97 o;
    o.pos = float4((v.p.x / viewSize.x) * 2.0 - 1.0,
                   1.0 - (v.p.y / viewSize.y) * 2.0, 0.0, 1.0);
    o.color = v.color;
    return o;
}
fragment float4 fsTri97(TriOut97 in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}
"""

final class XmasMetalCanvas97: MTKView {
    var onLayout97: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout97?()
    }
}

/// Metal 批量绘制器：图集＋实例缓冲＋每帧一次提交。
/// frameTick 在主线程备好实例后调用 MTKView.draw() 触发
/// delegate 编码（isPaused=true 手动驱动，与宿主时钟同拍）。
final class XmasMetalRenderer97: NSObject, MTKViewDelegate {
    private(set) var isReady = false
    private var pipelineSprite: MTLRenderPipelineState?
    private var pipelineTri: MTLRenderPipelineState?
    private var atlasTexture: MTLTexture?
    private(set) var lastSprCount98 = 0
    private(set) var lastTriCount98 = 0
    private var notexLogged98 = false
    private var uvRects: [CGRect] = []     // 精灵档下标→图集 UV
    private var instanceBuffer: MTLBuffer?
    private var triBuffer: MTLBuffer?
    private var commandQueue: MTLCommandQueue?
    private var pendingSprites: [XmasSpriteInstance97] = []
    private var pendingTris: [XmasSolidTri97] = []
    private var viewSizePt: CGSize = .zero
    private weak var deviceRef: MTLDevice?

    /// (99) 第 1 项：圣诞树纹理 v 轴翻转二分开关（键
    /// folia.xmas99.vflip，默认关）。真机日志分不开「v 轴行序
    /// 错位」与「颜色/alpha 错」，同一包内可切做真机对照：
    /// 开时在图集 UV 矩形生成处做 v' = 1 - v（见 buildAtlas）。
    static var vflip99: Bool {
        UserDefaults.standard.bool(forKey: "folia.xmas99.vflip")
    }

    private static let maxSprites = 20000
    private static let maxTris = 64

    func configure(view: XmasMetalCanvas97) {
        guard let device = view.device else { return }
        deviceRef = device
        commandQueue = device.makeCommandQueue()
        do {
            let lib = try device.makeLibrary(source: xmasShaderSource97, options: nil)
            func makePipeline(vs: String, fs: String) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: vs)
                d.fragmentFunction = lib.makeFunction(name: fs)
                let ca = d.colorAttachments[0]!
                ca.pixelFormat = view.colorPixelFormat
                ca.isBlendingEnabled = true
                ca.rgbBlendOperation = .add
                ca.alphaBlendOperation = .add
                ca.sourceRGBBlendFactor = .one
                ca.sourceAlphaBlendFactor = .one
                ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
                ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: d)
            }
            pipelineSprite = try makePipeline(vs: "vsSprite97", fs: "fsSprite97")
            pipelineTri = try makePipeline(vs: "vsTri97", fs: "fsTri97")
            instanceBuffer = device.makeBuffer(
                length: MemoryLayout<XmasSpriteInstance97>.stride * Self.maxSprites,
                options: [.storageModeShared])
            triBuffer = device.makeBuffer(
                length: MemoryLayout<XmasTriVert97>.stride * Self.maxTris * 3,
                options: [.storageModeShared])
            isReady = pipelineSprite != nil && pipelineTri != nil
                && instanceBuffer != nil && triBuffer != nil
                && commandQueue != nil
        } catch {
            isReady = false
        }
    }

    /// 精灵表→图集（shelf 打包，宽 4096；位图上下文预乘口径）。
    /// 返回 false 表示图集构建失败（调用方保留旧精灵账自证）。
    func buildAtlas(sprites: [CGImage?]) -> Bool {
        guard let device = deviceRef else { return false }
        let atlasW = 4096
        // shelf 打包：按高降序，行内左→右。
        let order = sprites.indices.sorted {
            (sprites[$0]?.height ?? 0) > (sprites[$1]?.height ?? 0)
        }
        var placements: [CGRect] = sprites.map { _ in .zero }
        var x = 0, y = 0, shelfH = 0
        for idx in order {
            guard let img = sprites[idx] else { continue }
            if x + img.width > atlasW { x = 0; y += shelfH; shelfH = 0 }
            placements[idx] = CGRect(x: x, y: y, width: img.width, height: img.height)
            x += img.width
            shelfH = max(shelfH, img.height)
        }
        let atlasH = y + shelfH
        guard atlasH > 0, atlasH <= 8192 else { return false }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: atlasW, height: atlasH, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return false }
        // (99) 第 1 项·内存：逐精灵分块上传，不再整幅图集 CPU
        // 暂存（旧路 raw＝4096×atlasH×4B≈15.7MB 整块分配，与纹理
        // 本体同量级、装配峰值翻倍）。位图口径不动：预乘 BGRA
        // （premultipliedFirst|byteOrder32Little，(98) 修正）；
        // 每块内翻转绘制使块内存行 0＝该精灵顶行，与旧整幅路
        // 逐行等价（旧路在整幅上下文里对每格做的正是同一翻转）。
        let cs = CGColorSpaceCreateDeviceRGB()
        for idx in sprites.indices {
            guard let img = sprites[idx] else { continue }
            let r = placements[idx]
            let w = Int(r.width), h = Int(r.height)
            guard w > 0, h > 0 else { continue }
            let bpr = w * 4
            var block = [UInt8](repeating: 0, count: bpr * h)
            let ok: Bool = block.withUnsafeMutableBytes { ptr in
                guard let ctx = CGContext(data: ptr.baseAddress, width: w,
                                          height: h, bitsPerComponent: 8,
                                          bytesPerRow: bpr, space: cs,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
                else { return false }
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return false }
            block.withUnsafeBytes { ptr in
                tex.replace(region: MTLRegionMake2D(Int(r.origin.x), Int(r.origin.y), w, h),
                            mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: bpr)
            }
        }
        atlasTexture = tex
        Breadcrumbs.log("p98 xmas uv atlasH=\(atlasH) uv13=\(placements.indices.contains(13) ? "\(placements[13])" : "na")")
        // (99) 第 1 项：v 翻转二分——UV 矩形处做 v' = 1 - v
        // （minY' = 1 - maxY、maxY' = 1 - minY），采样层其余不动。
        let vfl = Self.vflip99
        Breadcrumbs.log("p99 xmas vfl v=\(vfl ? 1 : 0)")
        uvRects = placements.map {
            let rect = CGRect(x: $0.origin.x / CGFloat(atlasW), y: $0.origin.y / CGFloat(atlasH),
                              width: $0.width / CGFloat(atlasW), height: $0.height / CGFloat(atlasH))
            return vfl
                ? CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
                : rect
        }
        return true
    }

    func uvRect(forSprite index: Int) -> CGRect? {
        guard uvRects.indices.contains(index), uvRects[index].width > 0 else { return nil }
        return uvRects[index]
    }

    /// 样式切出时释放图集纹理（内存纪律，沿旧 unmount 释放账）。
    func clearAtlas() {
        atlasTexture = nil
        uvRects = []
    }

    /// (99) 第 1 项·内存：退出彻底释放——图集之外，实例/三角
    /// 缓冲（20000×48B≈0.96MB 等）、管线与命令队列一并置空，
    /// 待提交帧数组清空。旧 unmount 只放图集，缓冲与管线靠
    /// 渲染器对象析构兜底，宿主持久复用时不释放。
    func releaseAll99() {
        clearAtlas()
        instanceBuffer = nil
        triBuffer = nil
        pipelineSprite = nil
        pipelineTri = nil
        commandQueue = nil
        pendingSprites = []
        pendingTris = []
        isReady = false
    }

    /// 一帧的实例集（渲染器在 frameTick 内备好，draw 时消费）。
    func submit(sprites: [XmasSpriteInstance97], tris: [XmasSolidTri97],
                viewSize: CGSize) {
        pendingSprites = sprites
        pendingTris = tris
        viewSizePt = viewSize
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard isReady,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let pipelineSprite, let pipelineTri,
              let instanceBuffer, let triBuffer, let commandQueue,
              viewSizePt.width > 0, viewSizePt.height > 0 else { return }
        var viewSize = SIMD2<Float>(Float(viewSizePt.width), Float(viewSizePt.height))
        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        // 固体三角形（远景剪影/树干，绘制序在精灵之前＝旧口径）。
        let triCount = min(pendingTris.count, Self.maxTris)
        if triCount > 0 {
            let ptr = triBuffer.contents()
                .bindMemory(to: XmasTriVert97.self, capacity: Self.maxTris * 3)
            for i in 0..<triCount {
                let t = pendingTris[i]
                ptr[i * 3] = XmasTriVert97(px: t.x0, py: t.y0, r: t.r, g: t.g, b: t.b, a: t.a)
                ptr[i * 3 + 1] = XmasTriVert97(px: t.x1, py: t.y1, r: t.r, g: t.g, b: t.b, a: t.a)
                ptr[i * 3 + 2] = XmasTriVert97(px: t.x2, py: t.y2, r: t.r, g: t.g, b: t.b, a: t.a)
            }
            enc.setRenderPipelineState(pipelineTri)
            enc.setVertexBuffer(triBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triCount * 3)
        }
        // 精灵实例。
        let sprCount = min(pendingSprites.count, Self.maxSprites)
        lastSprCount98 = sprCount
        lastTriCount98 = triCount
        if sprCount > 0 && atlasTexture == nil && !notexLogged98 {
            notexLogged98 = true
            Breadcrumbs.log("p98 xmas notex n=\(sprCount)")
        }
        if sprCount > 0, let atlasTexture {
            let ptr = instanceBuffer.contents()
                .bindMemory(to: XmasSpriteInstance97.self, capacity: Self.maxSprites)
            for i in 0..<sprCount { ptr[i] = pendingSprites[i] }
            enc.setRenderPipelineState(pipelineSprite)
            enc.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&viewSize, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
            enc.setFragmentTexture(atlasTexture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0,
                               vertexCount: sprCount * 6)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
