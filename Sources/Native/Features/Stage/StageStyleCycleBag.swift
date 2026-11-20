import Foundation
import UIKit

// 舞台样式长按轮换（3.7 (54) 工作流 R，Miller 2026-11-21 01:32
// 定）：舞台画面长按满 5 秒 → 按洗牌袋顺序切下一只歌词特效。
// 本文件三件：
//  - StageStyleCycleBag：洗牌袋状态（进程单例、纯内存——轮次
//    跨切歌/跨开台保留、冷启重建，不落盘）。
//  - StageCyclePressObserver：只观察按压起止的识别器（永不
//    识别、不取消触摸），供宿主在 5 秒等待期驱动进度环。
//  - StageCycleProgressRingView：按压进度环。
// 触发本体是宿主上的真 UILongPressGestureRecognizer
// （minimumPressDuration = holdDuration），切换落点在
// StageViewController.applyNativeStyleSelection /
// applyWebStyleSelection（与样式选择器同一通路）。

final class StageStyleCycleBag {

    static let shared = StageStyleCycleBag()

    /// 长按触发时长（Miller 口径：满 5 秒）。
    static let holdDuration: TimeInterval = 5
    /// 按压容忍位移：观察器撤环与触发识别器 allowableMovement
    /// 共用此值，手指漂移超限即整次长按作废。
    static let pressMoveTolerance: CGFloat = 12

    private init() {}

    /// 本轮余量（洗牌后的待切队列，队头先出）。不变量：当前
    /// 样式永不在余量内（next 取前对账 + noteExternalSelection
    /// 两处收口）。
    private var remaining: [String] = []
    /// 已开始的轮次序号（首次装填 = 1）；0 = 尚未开轮。
    private(set) var round = 0

    var remainingCount: Int { remaining.count }

    /// 可选全集（与样式选择器同源同序）：LyricStageRegistry
    /// 全部登记条目——已迁条目在选择器走原生切换、未迁条目
    /// 走网页兜底，两者在选择器里都可选，故全部入袋；注册
    /// 表之外不存在其他可选样式。
    static var selectableStyleIds: [String] {
        LyricStageRegistry.allStyles.sorted { $0.order < $1.order }.map { $0.id }
    }

    /// 外部选样式对账（选择器手选 / 提示条回网页 / 开台初始
    /// 样式 / 轮换自身落点都经此）：被选样式成为当前样式，
    /// 从本轮余量剔除——本轮内长按不会再切回刚被选走的同
    /// 一只。余量因此耗尽时，下一取自动开新轮。
    func noteExternalSelection(_ styleId: String) {
        remaining.removeAll { $0 == styleId }
    }

    /// 取下一只：先以当前样式对账（剔除当前样式与已不可选
    /// 的残留），余量空则开新轮——全集洗牌后剔除当前样式，
    /// 故新轮第一只必然不是刚切走的那只（强于「首只不同」
    /// 的口径：当前样式整轮不入袋，与不变量一致）。一轮内
    /// 每只至多递出一次。可选全集不足 2 只时返回 nil。
    func next(currentStyleId: String)
        -> (styleId: String, round: Int, remaining: Int)? {
        let selectable = Self.selectableStyleIds
        guard selectable.count > 1 else { return nil }
        remaining.removeAll { $0 == currentStyleId || !selectable.contains($0) }
        if remaining.isEmpty {
            round += 1
            remaining = selectable.shuffled()
            remaining.removeAll { $0 == currentStyleId }
            Breadcrumbs.log("style.cycle.round start round=\(round) size=\(remaining.count)")
        }
        let nextId = remaining.removeFirst()
        return (nextId, round, remaining.count)
    }
}

/// 长按进度观察器（工作流 R）：只观察所挂视图上单指按压的
/// 起点/位移/终结，永不进入识别态、不取消触摸、不与任何既
/// 有识别器互斥——同 SceneDelegate 的 TouchDownObserver-
/// Recognizer 先例。5 秒触发由真长按识别器负责，本观察器
/// 只驱动进度环：按下起环、漂移超限撤环、抬手/系统取消
/// 撤环。多指时只跟踪第一指（触发识别器 numberOfTouches-
/// Required 同为 1，第二指落下会令其失败、本观察器随其
/// touchesCancelled/Ended 一并收尾）。
final class StageCyclePressObserver: UIGestureRecognizer {

    var onPressBegan: ((CGPoint) -> Void)?
    var onPressMoved: ((CGPoint) -> Void)?
    var onPressEnded: (() -> Void)?

    private var trackedTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        onPressBegan?(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        onPressMoved?(trackedTouch.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        self.trackedTouch = nil
        onPressEnded?()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        self.trackedTouch = nil
        onPressEnded?()
        state = .failed
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}

/// 长按进度环（工作流 R）：44pt 暗底圆 + 白色描边环，环
/// strokeEnd 以与触发时长相同的 5 秒线性动画填充（计时填
/// 充非位移/转场动画，不用弹簧，与 iOS 口径不冲突）；出现
/// 走系统弹簧缩放淡入。取消 0.18s 淡出撤下，触发补满后
/// 0.3s 淡出。自身不接收触摸。
final class StageCycleProgressRingView: UIView {

    private let ringLayer = CAShapeLayer()
    private var dismissed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        isUserInteractionEnabled = false
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = UIColor.white.cgColor
        ringLayer.lineWidth = 3
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        layer.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        ringLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        ringLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ringLayer.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        ringLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5)).cgPath
    }

    /// 在 parent（rendererContainer）内以 center 为心显示并
    /// 开始填充；center 与坐标系均为 parent 坐标。
    func show(at center: CGPoint, in parent: UIView, duration: TimeInterval) {
        bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        self.center = center
        parent.addSubview(self)
        alpha = 0
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.25, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState]) {
            self.alpha = 1
            self.transform = .identity
        }
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0
        fill.toValue = 1
        fill.duration = duration
        fill.fillMode = .forwards
        fill.isRemovedOnCompletion = false
        ringLayer.add(fill, forKey: "cycleFill")
    }

    /// 撤环：completed = 已触发（环补满再淡出）；false = 未
    /// 满 5 秒取消（立即淡出）。重复调用为空操作。
    func dismiss(completed: Bool) {
        guard !dismissed else { return }
        dismissed = true
        if completed {
            ringLayer.removeAnimation(forKey: "cycleFill")
            ringLayer.strokeEnd = 1
        }
        UIView.animate(withDuration: completed ? 0.3 : 0.18,
                       options: [.beginFromCurrentState]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}
