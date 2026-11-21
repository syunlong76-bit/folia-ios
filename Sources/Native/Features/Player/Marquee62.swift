import SwiftUI
import UIKit

// (62) §5 歌名滚动 Marquee62：长标题在容器内横向滚动。
// 口径：只在文字宽度溢出容器时滚；启停走系统式缓动（停顿 →
// easeInOut 滚至尾 → 停顿 → 淡回收起），不用匀速线性无限滚
// （Miller 的 iOS 原生动效口径：禁线性匀速与突兀跳变，滚动
// 本体以 cubic easeInOut 分段近似系统滚动手感）。
// SwiftUI 侧以 UIViewRepresentable 挂载（MiniPlayerView 用）。

final class Marquee62View: UIView {

    var text: String = "" {
        didSet { if text != oldValue { rebuild() } }
    }
    var font: UIFont = .systemFont(ofSize: 14, weight: .medium) {
        didSet { rebuild() }
    }
    var textColor: UIColor = .white {
        didSet { label.textColor = textColor }
    }

    private let label = UILabel()
    private var animator: UIViewPropertyAnimator?
    private var cycleWork: DispatchWorkItem?
    private var overflowDistance: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuild()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopCycle() } else { rebuild() }
    }

    private func rebuild() {
        stopCycle()
        label.font = font
        label.textColor = textColor
        label.text = text
        label.sizeToFit()
        let textWidth = label.bounds.width
        label.frame = CGRect(x: 0, y: 0, width: textWidth,
                             height: bounds.height)
        label.center.y = bounds.height / 2
        overflowDistance = textWidth - bounds.width
        guard bounds.width > 0, overflowDistance > 4 else {
            label.frame.origin.x = 0
            return
        }
        scheduleScroll(delay: 1.4)
    }

    private func scheduleScroll(delay: TimeInterval) {
        cycleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scrollToEnd() }
        cycleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scrollToEnd() {
        guard window != nil, overflowDistance > 4 else { return }
        let distance = overflowDistance + 12
        let animator = UIViewPropertyAnimator(
            duration: TimeInterval(distance / 42),
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.42, y: 0),
                controlPoint2: CGPoint(x: 0.58, y: 1)))
        animator.addAnimations { [weak self] in
            self?.label.frame.origin.x = -distance
        }
        animator.addCompletion { [weak self] _ in
            self?.scheduleReset()
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func scheduleReset() {
        cycleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.3, delay: 0,
                           options: [.curveEaseInOut]) {
                self.label.alpha = 0
            } completion: { _ in
                self.label.frame.origin.x = 0
                UIView.animate(withDuration: 0.3) { self.label.alpha = 1 }
                self.scheduleScroll(delay: 0.9)
            }
        }
        cycleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func stopCycle() {
        cycleWork?.cancel()
        cycleWork = nil
        animator?.stopAnimation(true)
        animator = nil
        label.alpha = 1
    }
}

struct Marquee62: UIViewRepresentable {
    let text: String
    var font: UIFont = .systemFont(ofSize: 14, weight: .medium)
    var textColor: UIColor = .white

    func makeUIView(context: Context) -> Marquee62View {
        let view = Marquee62View()
        view.font = font
        view.textColor = textColor
        view.text = text
        return view
    }

    func updateUIView(_ uiView: Marquee62View, context: Context) {
        uiView.font = font
        uiView.textColor = textColor
        uiView.text = text
    }
}
