import UIKit

// 浮名 fume · 相机（照搬 folia-major 网页版 fumeCamera.ts +
// fumeCameraStep.ts）：焦点点位（stepped/smooth 两式）、换目标
// 时长、总览镜头与长距离「经总览点」桥接飞行、空闲漂移、
// 弹簧步进（focus 先行 + 弹簧追赶）逐项移植。状态只由宿主
// frameTick 喂入的 position/dt 推进，本文件不建任何时钟源；
// now（漂移相位）由渲染方以 CACurrentMediaTime 传入，与协议
// 锚点同基准。
//
// 已知口径差：动画强度（animationIntensity）协议不传，原生
// 恒用网页 normal 档漂移参数（distance 18 / duration 7 /
// scaleAmplitude 0.011）。

let fumeCameraScaleMin = 0.22
let fumeCameraScaleMax = 2.24
let fumeOverviewSource = -2
private let fumeTeleportTriggerScreens = 2.75

struct FumeCameraTarget {
    var x: Double = 0
    var y: Double = 0
    var velocityX: Double = 0
    var velocityY: Double = 0
    var focusX: Double = 0
    var focusY: Double = 0
    var scale: Double = 1
    var velocityScale: Double = 0
    var focusScale: Double = 1
}

struct FumeRetargetState {
    var sourceLineIndex: Int = -1
    var startedAt: TimeInterval = 0
    var duration: Double = 0.18
    var fromX: Double = 0
    var fromY: Double = 0
    var fromScale: Double = 1
    var bridgeMode: Int = 0   // 0 none / 1 direct / 2 overview
    var bridgeWaypointX: Double = 0
    var bridgeWaypointY: Double = 0
    var bridgeWaypointScale: Double = 1
    var bridgeWaypointPhase: Double = 0.36
}

struct FumeViewTarget {
    var x: Double
    var y: Double
    var scale: Double
}

// MARK: - 焦点点位（fumeCamera.ts）

private func fumePointOnRenderLine(block: FumeBlockData, lineIndex: Int, offset: Double)
    -> (x: Double, y: Double) {
    let renderLine = block.renderLines[lineIndex]
    let clamped = fumeClamp(offset, Double(renderLine.start), Double(renderLine.end))
    let baseOffset = Int(floor(clamped))
    let fraction = clamped - Double(baseOffset)
    let localBase = baseOffset - renderLine.start
    let baseWidth: CGFloat = (localBase >= 0 && localBase < renderLine.glyphOffsets.count)
        ? renderLine.glyphOffsets[localBase] : 0
    var advance: CGFloat = 0
    if localBase >= 0 && localBase < renderLine.graphemes.count {
        let current = localBase < renderLine.glyphOffsets.count ? renderLine.glyphOffsets[localBase] : 0
        let next = localBase + 1 < renderLine.glyphOffsets.count
            ? renderLine.glyphOffsets[localBase + 1] : renderLine.width
        advance = max(next - current, 0)
    }
    let minX = Double(block.x + renderLine.left)
    let maxX = minX + Double(renderLine.width)
    return (
        x: fumeClamp(minX + Double(baseWidth) + Double(advance) * fraction, minX, maxX),
        y: Double(block.y + renderLine.top + block.lineHeight * 0.5))
}

/// stepped：按已印字素整数定位（resolveSteppedBlockFocusPoint）。
func fumeSteppedFocusPoint(block: FumeBlockData, printedCount: Int) -> (x: Double, y: Double) {
    if block.renderLines.isEmpty {
        return (Double(block.x + block.width * 0.5), Double(block.y + block.height * 0.5))
    }
    let effective = fumeClamp(Double(printedCount), 0, Double(block.graphemes.count))
    var lineIndex = block.renderLines.firstIndex { effective <= Double($0.end) }
        ?? (block.renderLines.count - 1)
    lineIndex = max(lineIndex, 0)
    let renderLine = block.renderLines[lineIndex]
    let local = fumeClamp(effective, Double(renderLine.start), Double(renderLine.end))
    let localIdx = Int(local) - renderLine.start
    let width: CGFloat = (localIdx >= 0 && localIdx < renderLine.glyphOffsets.count)
        ? renderLine.glyphOffsets[localIdx] : renderLine.width
    let minX = Double(block.x + renderLine.left)
    let maxX = minX + Double(renderLine.width)
    return (
        x: fumeClamp(minX + Double(width), minX, maxX),
        y: Double(block.y + renderLine.top + block.lineHeight * 0.5))
}

/// smooth：按小数进度定位，跨行 0.7 字素窗内与邻行混合
/// （resolveSmoothBlockFocusPoint）。
func fumeSmoothFocusPoint(block: FumeBlockData, printedProgress: Double) -> (x: Double, y: Double) {
    if block.renderLines.isEmpty {
        return (Double(block.x + block.width * 0.5), Double(block.y + block.height * 0.5))
    }
    let effective = fumeClamp(printedProgress, 0, Double(block.graphemes.count))
    var targetIndex = block.renderLines.firstIndex { effective <= Double($0.end) }
        ?? (block.renderLines.count - 1)
    targetIndex = max(targetIndex, 0)
    var point = fumePointOnRenderLine(block: block, lineIndex: targetIndex, offset: effective)
    let current = block.renderLines[targetIndex]
    let blendWindow = 0.7
    if targetIndex > 0 && effective < Double(current.start) + blendWindow {
        let previous = block.renderLines[targetIndex - 1]
        let blend = fumeEaseInOutCubic(fumeClamp(
            1 - ((effective - Double(previous.end)) / blendWindow), 0, 1))
        let previousPoint = fumePointOnRenderLine(block: block, lineIndex: targetIndex - 1, offset: Double(previous.end))
        point = (x: fumeMix(point.x, previousPoint.x, blend),
                 y: fumeMix(point.y, previousPoint.y, blend))
    } else if targetIndex < block.renderLines.count - 1
        && effective > Double(current.end) - blendWindow {
        let next = block.renderLines[targetIndex + 1]
        let blend = fumeEaseInOutCubic(fumeClamp(
            (effective - (Double(current.end) - blendWindow)) / blendWindow, 0, 1))
        let nextPoint = fumePointOnRenderLine(block: block, lineIndex: targetIndex + 1, offset: Double(next.start))
        point = (x: fumeMix(point.x, nextPoint.x, blend),
                 y: fumeMix(point.y, nextPoint.y, blend))
    }
    return point
}

/// resolveBlockEntryFocusPoint：块首行行首。
func fumeEntryFocusPoint(block: FumeBlockData) -> (x: Double, y: Double) {
    guard let first = block.renderLines.first else {
        return (Double(block.x + block.width * 0.5), Double(block.y + block.height * 0.5))
    }
    return (Double(block.x + first.left),
            Double(block.y + first.top + block.lineHeight * 0.5))
}

/// resolveCameraScaleForBlock：目标行高 = clamp(短边×0.115, 64, 124)。
func fumeCameraScale(for block: FumeBlockData, viewport: CGSize) -> Double {
    let minSide = max(min(viewport.width, viewport.height), 1)
    let targetLineHeight = fumeClamp(Double(minSide) * 0.115, 64, 124)
    return fumeClamp(targetLineHeight / max(Double(block.lineHeight), 1), 0.88, 2.2)
}

func fumeOverviewRetargetDuration(viewport: CGSize) -> Double {
    fumeClamp(Double(min(viewport.width, viewport.height)) / 1500, 0.38, 0.58)
}

/// resolveArticleOverviewCamera：全文总览镜头。
func fumeOverviewCamera(article: FumeArticleData, viewport: CGSize) -> FumeViewTarget {
    if article.blocks.isEmpty {
        let fit = min(Double(viewport.width) / max(Double(article.width), 1),
                      Double(viewport.height) / max(Double(article.height), 1))
        return FumeViewTarget(x: Double(article.width) * 0.5, y: Double(article.height) * 0.5,
                              scale: fumeClamp(fit * 0.92, fumeCameraScaleMin, 0.72))
    }
    var minX = Double.infinity, minY = Double.infinity
    var maxX = -Double.infinity, maxY = -Double.infinity
    for block in article.blocks {
        minX = min(minX, Double(block.x))
        minY = min(minY, Double(block.y))
        maxX = max(maxX, Double(block.x + block.width))
        maxY = max(maxY, Double(block.y + block.height))
    }
    let paddingX = fumeClamp(Double(viewport.width) * 0.2, 120, 280)
    let paddingY = fumeClamp(Double(viewport.height) * 0.2, 96, 220)
    let framedWidth = max(maxX - minX + paddingX * 2, 1)
    let framedHeight = max(maxY - minY + paddingY * 2, 1)
    let fit = min(Double(viewport.width) / framedWidth, Double(viewport.height) / framedHeight)
    return FumeViewTarget(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5,
                          scale: fumeClamp(fit, fumeCameraScaleMin, 0.72))
}

/// resolveOverviewFlightBridge：远距离换目标时经总览点绕飞。
func fumeOverviewFlightBridge(fromX: Double, fromY: Double, fromScale: Double,
                              targetX: Double, targetY: Double, targetScale: Double,
                              overview: FumeViewTarget?, viewport: CGSize)
    -> (x: Double, y: Double, scale: Double, phase: Double, duration: Double)? {
    guard let overview else { return nil }
    let safeScale = max(fromScale, targetScale, overview.scale, 0.001)
    let minSide = max(min(viewport.width, viewport.height), 1)
    let worldDistance = hypot(fromX - targetX, fromY - targetY)
    let screenDistance = worldDistance * safeScale
    if worldDistance <= 0 || screenDistance < Double(minSide) * fumeTeleportTriggerScreens {
        return nil
    }
    let loft = fumeClamp((screenDistance / Double(minSide) - fumeTeleportTriggerScreens) / 3.4, 0, 1)
    let midX = fumeMix(fromX, targetX, 0.5)
    let midY = fumeMix(fromY, targetY, 0.5)
    let bias = fumeMix(0.18, 0.42, loft)
    let waypointX = fumeMix(midX, overview.x, bias)
    let waypointY = fumeMix(midY, overview.y, bias)
    let endpointScale = max(fromScale, targetScale, 0.001)
    let lofted = endpointScale * fumeMix(0.62, 0.4, loft)
    let overviewLimited = overview.scale * fumeMix(1.85, 1.55, loft)
    let waypointScale = fumeClamp(max(lofted, overviewLimited),
                                  fumeCameraScaleMin, max(endpointScale * 0.92, fumeCameraScaleMin))
    let distanceFromStart = hypot(waypointX - fromX, waypointY - fromY) * max(fromScale, waypointScale, 0.001)
    let distanceToTarget = hypot(targetX - waypointX, targetY - waypointY) * max(targetScale, waypointScale, 0.001)
    let totalLeg = distanceFromStart + distanceToTarget
    let phase = totalLeg <= 0 ? 0.36 : fumeClamp(distanceFromStart / totalLeg, 0.26, 0.44)
    let duration = fumeClamp(0.26 + (screenDistance / (Double(minSide) * 5.5)) * 0.28, 0.3, 0.68)
    return (waypointX, waypointY, waypointScale, phase, duration)
}

/// resolveFocusBlock：当前行块优先；其后按网页回退链。
func fumeFocusBlock(article: FumeArticleData, lineIndex: Int, time: TimeInterval) -> FumeBlockData? {
    if lineIndex >= 0, let idx = article.blockIndexBySourceLine[lineIndex] {
        return article.blocks[idx]
    }
    if let lastIdx = article.chronological.last {
        let last = article.blocks[lastIdx]
        if time >= article.lastRenderEnd { return last }
    }
    for idx in article.chronological.reversed() {
        let block = article.blocks[idx]
        let printed = fumePrintedCount(line: block.line, ranges: block.wordRanges,
                                       graphemeCount: block.graphemes.count, at: time)
        if printed > 0 { return block }
    }
    if let firstIdx = article.chronological.first {
        return article.blocks[firstIdx]
    }
    return nil
}

// MARK: - 相机状态与步进（fumeCameraStep.ts 移植）

struct FumeCameraState {
    var camera = FumeCameraTarget()
    var retarget = FumeRetargetState()
    var initialized = false

    /// syncFumeCameraToArticle：新文章落位（文章中心、scale 1.18）。
    mutating func syncToArticle(_ article: FumeArticleData?) {
        guard let article else { initialized = false; return }
        if !initialized {
            camera = FumeCameraTarget(
                x: Double(article.width) * 0.5, y: Double(article.height) * 0.5,
                velocityX: 0, velocityY: 0,
                focusX: Double(article.width) * 0.5, focusY: Double(article.height) * 0.5,
                scale: 1.18, velocityScale: 0, focusScale: 1.18)
            initialized = true
        } else {
            camera.x = fumeClamp(camera.x, 0, Double(article.width))
            camera.y = fumeClamp(camera.y, 0, Double(article.height))
            camera.focusX = fumeClamp(camera.focusX, 0, Double(article.width))
            camera.focusY = fumeClamp(camera.focusY, 0, Double(article.height))
            camera.scale = fumeClamp(camera.scale, fumeCameraScaleMin, fumeCameraScaleMax)
            camera.focusScale = fumeClamp(camera.focusScale, fumeCameraScaleMin, fumeCameraScaleMax)
        }
    }

    /// stepFumeCamera 的逐帧步进。返回总览恢复进度（0…1）。
    mutating func step(article: FumeArticleData, time: TimeInterval, nowMs: Double,
                       dt: Double, lineIndex: Int, viewport: CGSize,
                       overview: FumeViewTarget?, overviewStart: TimeInterval,
                       cameraSpeed: Double, stepped: Bool,
                       staticMode: Bool) -> Double {
        let focusBlock = fumeFocusBlock(article: article, lineIndex: lineIndex, time: time)
        let shouldShowOverview = overview != nil && time >= overviewStart
        var targetX = Double(article.width) * 0.5
        var targetY = Double(article.height) * 0.5
        var targetScale = 1.18
        var entryPoint: (x: Double, y: Double)? = nil
        var didRetarget = false

        if shouldShowOverview, let overview {
            targetX = overview.x
            targetY = overview.y
            targetScale = overview.scale
            if retarget.sourceLineIndex != fumeOverviewSource {
                retarget = FumeRetargetState(
                    sourceLineIndex: fumeOverviewSource, startedAt: time,
                    duration: fumeClamp(fumeOverviewRetargetDuration(viewport: viewport) / cameraSpeed, 0.12, 1.2),
                    fromX: camera.x, fromY: camera.y, fromScale: camera.scale)
                didRetarget = true
            }
        } else if let block = focusBlock {
            let focusPoint: (x: Double, y: Double)
            if stepped {
                focusPoint = fumeSteppedFocusPoint(
                    block: block,
                    printedCount: fumePrintedCount(line: block.line, ranges: block.wordRanges,
                                                   graphemeCount: block.graphemes.count, at: time))
            } else {
                focusPoint = fumeSmoothFocusPoint(
                    block: block,
                    printedProgress: fumePrintedProgress(line: block.line, ranges: block.wordRanges,
                                                         graphemeCount: block.graphemes.count, at: time))
            }
            entryPoint = fumeEntryFocusPoint(block: block)
            targetX = focusPoint.x
            targetY = focusPoint.y
            targetScale = fumeCameraScale(for: block, viewport: viewport)
            if retarget.sourceLineIndex != block.sourceLineIndex {
                retarget = FumeRetargetState(
                    sourceLineIndex: block.sourceLineIndex, startedAt: time,
                    duration: fumeClamp(fumeCameraRetargetDuration(for: block.line) / cameraSpeed, 0.03, 0.3),
                    fromX: camera.x, fromY: camera.y, fromScale: camera.scale)
                didRetarget = true
            }
        } else if retarget.sourceLineIndex != -1 {
            retarget = FumeRetargetState(
                sourceLineIndex: -1, startedAt: time,
                duration: fumeClamp(0.18 / cameraSpeed, 0.05, 0.4),
                fromX: camera.x, fromY: camera.y, fromScale: camera.scale)
            didRetarget = true
        }

        let elapsed = max(time - retarget.startedAt, 0)
        let phase = fumeClamp(elapsed / max(retarget.duration, 0.001), 0, 1)
        let overviewRestore = (shouldShowOverview && retarget.sourceLineIndex == fumeOverviewSource)
            ? fumeEaseInOutCubic(phase) : 0
        let boost = 1 - fumeEaseOutCubic(phase)
        let entryBias = pow(boost, 0.58)

        if let entryPoint {
            targetX = fumeMix(targetX, entryPoint.x, entryBias)
            targetY = fumeMix(targetY, entryPoint.y, entryBias)
        }

        if !staticMode {
            // 空闲漂移（normal 档：distance 18 / duration 7s / scaleAmp 0.011）。
            let floatPhase = (nowMs / 1000 / 7) * Double.pi * 2
            let attenuation = shouldShowOverview ? 0.36 : 1.0
            let screenFloatX = sin(floatPhase * 0.74 + 0.8) * 18 * 0.34
            let screenFloatY = (sin(floatPhase) * 18 + sin(floatPhase * 0.5 + 1.1) * 18 * 0.22) * attenuation
            let divisor = max(targetScale, 0.001)
            targetX -= screenFloatX / divisor
            targetY -= screenFloatY / divisor
            targetScale = fumeClamp(
                targetScale * (1 + sin(floatPhase + 0.9) * 0.011 * attenuation),
                fumeCameraScaleMin, fumeCameraScaleMax)
        }

        if didRetarget {
            let bridgeScale = max(camera.scale, targetScale, 0.001)
            let screenDistance = hypot(abs(targetX - retarget.fromX) * bridgeScale,
                                       abs(targetY - retarget.fromY) * bridgeScale)
            retarget.bridgeMode = screenDistance >= Double(min(viewport.width, viewport.height)) * 0.42 ? 1 : 0
            retarget.bridgeWaypointX = targetX
            retarget.bridgeWaypointY = targetY
            retarget.bridgeWaypointScale = targetScale
            retarget.bridgeWaypointPhase = 0.5
            if retarget.sourceLineIndex >= 0,
               let bridge = fumeOverviewFlightBridge(
                    fromX: retarget.fromX, fromY: retarget.fromY, fromScale: retarget.fromScale,
                    targetX: targetX, targetY: targetY, targetScale: targetScale,
                    overview: overview, viewport: viewport) {
                retarget.bridgeMode = 2
                retarget.bridgeWaypointX = bridge.x
                retarget.bridgeWaypointY = bridge.y
                retarget.bridgeWaypointScale = bridge.scale
                retarget.bridgeWaypointPhase = bridge.phase
                retarget.duration = max(retarget.duration,
                                        fumeClamp(bridge.duration / cameraSpeed, 0.16, 0.9))
            }
        }

        let cameraDistance = hypot(targetX - camera.x, targetY - camera.y)
        let useBridge = retarget.bridgeMode != 0 && phase < 1

        if useBridge {
            var bridgedX = targetX
            var bridgedY = targetY
            var bridgedScale = targetScale
            if retarget.bridgeMode == 2 {
                let bridgePhase = fumeEaseOutCubic(phase)
                bridgedX = fumeQuadraticBezier(retarget.fromX, retarget.bridgeWaypointX, targetX, bridgePhase)
                bridgedY = fumeQuadraticBezier(retarget.fromY, retarget.bridgeWaypointY, targetY, bridgePhase)
                bridgedScale = fumeQuadraticBezier(retarget.fromScale, retarget.bridgeWaypointScale, targetScale, bridgePhase)
            } else {
                let bridgePhase = fumeEaseInOutCubic(phase)
                bridgedX = fumeMix(retarget.fromX, targetX, bridgePhase)
                bridgedY = fumeMix(retarget.fromY, targetY, bridgePhase)
                bridgedScale = fumeMix(retarget.fromScale, targetScale, bridgePhase)
            }
            let catchUp = 1 - exp(-dt * (retarget.bridgeMode == 2
                ? fumeMix(12.5, 22, 1 - phase)
                : fumeMix(10.5, 17.5, 1 - phase)))
            camera.focusX = bridgedX
            camera.focusY = bridgedY
            camera.focusScale = bridgedScale
            camera.x += (bridgedX - camera.x) * catchUp
            camera.y += (bridgedY - camera.y) * catchUp
            camera.scale += (bridgedScale - camera.scale) * catchUp
            camera.scale = fumeClamp(camera.scale, fumeCameraScaleMin, fumeCameraScaleMax)
            // iOS 帧率口径：速度衰减按 dt×60 折合帧数（网页 iOS 分支同式）。
            let decayFrames = dt * 60
            camera.velocityX *= pow(0.72, decayFrames)
            camera.velocityY *= pow(0.72, decayFrames)
            camera.velocityScale *= pow(0.68, decayFrames)
        } else {
            let boostedRate = fumeClamp(4.8 / max(retarget.duration, 0.05), 20, 54)
            let targetCatchUp = 1 - exp(-dt * fumeMix(11.2, boostedRate, boost))
            camera.focusX += (targetX - camera.focusX) * targetCatchUp
            camera.focusY += (targetY - camera.focusY) * targetCatchUp
            camera.focusScale += (targetScale - camera.focusScale)
                * (1 - exp(-dt * fumeMix(5.4, 12.8, boost)))

            let springStrength = fumeMix(
                208,
                fumeClamp(15.8 / max(retarget.duration * retarget.duration, 0.0064), 260, 780),
                boost)
            let damping = fumeMix(
                24,
                fumeClamp(sqrt(springStrength) * 1.36, 24, 40),
                boost)
            let accelX = (camera.focusX - camera.x) * springStrength - camera.velocityX * damping
            let accelY = (camera.focusY - camera.y) * springStrength - camera.velocityY * damping
            camera.velocityX += accelX * dt
            camera.velocityY += accelY * dt
            let maxVelocity = fumeMix(
                1320,
                fumeClamp(cameraDistance / max(retarget.duration * 0.28, 0.028), 2600, 8800),
                boost)
            camera.velocityX = fumeClamp(camera.velocityX, -maxVelocity, maxVelocity)
            camera.velocityY = fumeClamp(camera.velocityY, -maxVelocity, maxVelocity)
            camera.x += camera.velocityX * dt
            camera.y += camera.velocityY * dt

            let scaleStrength = fumeMix(54, 108, boost)
            let scaleDamping = fumeMix(13.5, 21, boost)
            let accelScale = (camera.focusScale - camera.scale) * scaleStrength
                - camera.velocityScale * scaleDamping
            camera.velocityScale += accelScale * dt
            camera.velocityScale = fumeClamp(camera.velocityScale, -1.6, 1.6)
            camera.scale += camera.velocityScale * dt
            camera.scale = fumeClamp(camera.scale, fumeCameraScaleMin, fumeCameraScaleMax)
        }
        return overviewRestore
    }
}

// MARK: - 背景视差（fumeCameraStep.resolveFumeBackgroundView）

/// 背景相机：视差 X 0.9 / Y 0.74、缩放 ×0.94、下移
/// clamp(视口高×0.22/scale, 48, 180)。
func fumeBackgroundView(sceneWidth: CGFloat, sceneHeight: CGFloat,
                        camera: FumeCameraTarget, viewport: CGSize)
    -> (centerX: Double, centerY: Double, cameraX: Double, cameraY: Double, scale: Double) {
    let centerX = Double(sceneWidth) * 0.5
    let centerY = Double(sceneHeight) * 0.5
    let verticalOffset = fumeClamp(
        Double(viewport.height) * 0.22 / max(camera.scale, 0.001), 48, 180)
    let bgX = fumeMix(centerX, camera.x, 0.9)
    let bgY = fumeMix(centerY, camera.y, 0.74) - verticalOffset
    let bgScale = fumeClamp(camera.scale * 0.94, fumeCameraScaleMin, fumeCameraScaleMax)
    return (centerX, centerY, bgX, bgY, bgScale)
}
