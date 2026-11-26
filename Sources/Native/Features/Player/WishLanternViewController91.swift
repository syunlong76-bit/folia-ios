import UIKit

/// port91（任务 6）：孔明灯许愿页重设计（样板 folia-91-yang-ban
/// 许愿灯视图定版）——整页氛围面（压暗层透出原页面、特效不换
/// 背景口径不变）、大灯居中＋暖光晕、输入文字实时落在灯纸上
/// （楷体、深棕）、取消/放飞齐全、放飞升空缩小淡出后由引擎
/// 真放飞一盏愿望灯。替换 GlobalFx87 旧 UIAlertController 形
/// 态；入口仍是原写灯钮（wishButtonTapped 转呈本页）。
final class WishLanternViewController91: UIViewController, UITextViewDelegate {

    /// 放飞回调（文案已在本页收口：空→默认愿、截 60 字）。
    var onRelease: ((String) -> Void)?

    private let floatGroup = UIView()
    private let glowLayer = CAGradientLayer()
    private let lanternView = UIView()
    private let bodyGradient = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let releaseButton = UIButton(type: .system)
    private var lanternWidthC: NSLayoutConstraint?
    private var released = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)

        // 大灯组（光晕＋灯体＋灯纸文字）居中偏上。
        floatGroup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatGroup)
        glowLayer.type = .radial
        glowLayer.colors = [
            UIColor(red: 1, green: 146 / 255, blue: 74 / 255, alpha: 0.35).cgColor,
            UIColor(red: 1, green: 124 / 255, blue: 60 / 255, alpha: 0.10).cgColor,
            UIColor(red: 1, green: 110 / 255, blue: 48 / 255, alpha: 0).cgColor,
        ]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        floatGroup.layer.addSublayer(glowLayer)

        lanternView.translatesAutoresizingMaskIntoConstraints = false
        floatGroup.addSubview(lanternView)
        bodyGradient.colors = [
            UIColor(red: 1, green: 190 / 255, blue: 132 / 255, alpha: 0.96).cgColor,
            UIColor(red: 1, green: 150 / 255, blue: 94 / 255, alpha: 0.97).cgColor,
            UIColor(red: 248 / 255, green: 116 / 255, blue: 74 / 255, alpha: 0.98).cgColor,
            UIColor(red: 1, green: 164 / 255, blue: 102 / 255, alpha: 0.99).cgColor,
        ]
        bodyGradient.locations = [0, 0.38, 0.75, 1]
        bodyGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bodyGradient.endPoint = CGPoint(x: 0.5, y: 1)
        bodyGradient.mask = bodyMask
        lanternView.layer.addSublayer(bodyGradient)
        mouthLayer.fillColor = UIColor(red: 1, green: 214 / 255, blue: 110 / 255, alpha: 0.97).cgColor
        lanternView.layer.addSublayer(mouthLayer)

        // 灯纸文字：楷体、深棕，与引擎灯上字同色口径。
        textView.backgroundColor = .clear
        textView.textColor = UIColor(red: 74 / 255, green: 26 / 255, blue: 4 / 255, alpha: 0.85)
        textView.font = Self.kaiFont(size: 20)
        textView.textAlignment = .center
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        lanternView.addSubview(textView)
        placeholderLabel.text = "把秘密写在这盏灯上…"
        placeholderLabel.font = Self.kaiFont(size: 15)
        placeholderLabel.textColor = UIColor(red: 74 / 255, green: 26 / 255, blue: 4 / 255, alpha: 0.45)
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        lanternView.addSubview(placeholderLabel)

        // 钮排：取消（描边）＋放飞（暖渐变实心）。
        for (button, title) in [(cancelButton, "取消"), (releaseButton, "放飞")] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.layer.cornerRadius = 22
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 104),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
        }
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.layer.borderWidth = 1
        cancelButton.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        cancelButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        releaseButton.setTitleColor(UIColor(red: 36 / 255, green: 19 / 255, blue: 0, alpha: 1), for: .normal)
        let relGrad = CAGradientLayer()
        relGrad.colors = [
            UIColor(red: 1, green: 176 / 255, blue: 46 / 255, alpha: 1).cgColor,
            UIColor(red: 1, green: 125 / 255, blue: 84 / 255, alpha: 1).cgColor,
        ]
        relGrad.startPoint = CGPoint(x: 0, y: 0)
        relGrad.endPoint = CGPoint(x: 1, y: 1)
        relGrad.frame = CGRect(x: 0, y: 0, width: 104, height: 44)
        relGrad.cornerRadius = 22
        releaseButton.layer.insertSublayer(relGrad, at: 0)
        releaseButton.addTarget(self, action: #selector(releaseTapped), for: .touchUpInside)

        lanternWidthC = lanternView.widthAnchor.constraint(equalToConstant: 216)
        NSLayoutConstraint.activate([
            floatGroup.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            floatGroup.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -52),
            floatGroup.widthAnchor.constraint(equalTo: lanternView.widthAnchor, multiplier: 1.9),
            floatGroup.heightAnchor.constraint(equalTo: lanternView.heightAnchor, multiplier: 1.9),
            lanternView.centerXAnchor.constraint(equalTo: floatGroup.centerXAnchor),
            lanternView.centerYAnchor.constraint(equalTo: floatGroup.centerYAnchor),
            lanternWidthC!,
            lanternView.heightAnchor.constraint(equalTo: lanternView.widthAnchor, multiplier: 1.4),
            textView.centerXAnchor.constraint(equalTo: lanternView.centerXAnchor),
            textView.centerYAnchor.constraint(equalTo: lanternView.centerYAnchor, constant: -8),
            textView.widthAnchor.constraint(equalTo: lanternView.widthAnchor, multiplier: 0.58),
            textView.heightAnchor.constraint(equalTo: lanternView.heightAnchor, multiplier: 0.42),
            placeholderLabel.centerXAnchor.constraint(equalTo: textView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.widthAnchor.constraint(equalTo: textView.widthAnchor),
            cancelButton.topAnchor.constraint(equalTo: floatGroup.bottomAnchor, constant: -34),
            cancelButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -10),
            releaseButton.topAnchor.constraint(equalTo: cancelButton.topAnchor),
            releaseButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 10),
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardMoved(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        Breadcrumbs.log("p91 wish view")
    }

    /// 楷体取字：Kaiti SC 优先，缺失退系统衬线（不造假字体名链）。
    private static func kaiFont(size: CGFloat) -> UIFont {
        for name in ["Kaiti SC", "STKaiti", "KaiTi"] {
            if let font = UIFont(name: name, size: size) { return font }
        }
        return UIFont.systemFont(ofSize: size, weight: .medium)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 横竖屏双适配：横屏灯收小（样板 216 → 172 口径）。
        let landscape = view.bounds.width > view.bounds.height
        let target: CGFloat = landscape ? 172 : 216
        if let c = lanternWidthC, abs(c.constant - target) > 0.5 { c.constant = target }
        let lb = lanternView.bounds
        glowLayer.frame = floatGroup.bounds
        bodyGradient.frame = lb
        bodyMask.path = Self.bodyPath(in: lb).cgPath
        // 灯口亮椭圆（底部开口）。
        let wb = lb.width * 0.30
        mouthLayer.path = UIBezierPath(ovalIn: CGRect(
            x: lb.midX - wb, y: lb.height - wb * 0.62,
            width: wb * 2, height: wb * 0.62)).cgPath
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 灯体浮动（样板 floaty 5.2s 上下漂）。
        UIView.animate(withDuration: 5.2, delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut]) {
            self.floatGroup.transform = CGAffineTransform(translationX: 0, y: -7)
        }
        textView.becomeFirstResponder()
    }

    /// 灯体轮廓（与引擎 drawLantern 同比例：顶半宽 .37w、底
    /// 半宽 .30w、两侧贝塞尔收束）。
    private static func bodyPath(in rect: CGRect) -> UIBezierPath {
        let w = rect.width, h = rect.height
        let wt = w * 0.37, wb = w * 0.30
        let cx = rect.midX, top = rect.minY, bottom = rect.maxY
        let path = UIBezierPath()
        path.move(to: CGPoint(x: cx - wt, y: top + h * 0.02))
        path.addQuadCurve(to: CGPoint(x: cx + wt, y: top + h * 0.02),
                          controlPoint: CGPoint(x: cx, y: top - h * 0.045))
        path.addCurve(to: CGPoint(x: cx + wb, y: bottom),
                      controlPoint1: CGPoint(x: cx + w * 0.50, y: top + h * 0.30),
                      controlPoint2: CGPoint(x: cx + w * 0.50, y: top + h * 0.68))
        path.addLine(to: CGPoint(x: cx - wb, y: bottom))
        path.addCurve(to: CGPoint(x: cx - wt, y: top + h * 0.02),
                      controlPoint1: CGPoint(x: cx - w * 0.50, y: top + h * 0.68),
                      controlPoint2: CGPoint(x: cx - w * 0.50, y: top + h * 0.30))
        path.close()
        return path
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        if textView.text.count > 60 {
            textView.text = String(textView.text.prefix(60))
        }
    }

    @objc private func keyboardMoved(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect else { return }
        let overlap = max(0, view.bounds.height - frame.minY)
        UIView.animate(withDuration: 0.3) {
            self.view.transform = overlap > 0
                ? CGAffineTransform(translationX: 0, y: -overlap * 0.35) : .identity
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func releaseTapped() {
        guard !released else { return }
        released = true
        let raw = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = raw.isEmpty ? "愿心想事成" : String(raw.prefix(60))
        textView.resignFirstResponder()
        floatGroup.layer.removeAllAnimations()
        cancelButton.isEnabled = false
        releaseButton.isEnabled = false
        // 放飞：升空＋缩小＋淡出（样板 fly：−46vh、scale .24、
        // 2.6s；iOS 系统弹簧口径）。
        UIView.animate(withDuration: 2.6, delay: 0,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0.25,
                       options: [.curveEaseIn]) {
            self.floatGroup.transform = CGAffineTransform(
                translationX: 0, y: -self.view.bounds.height * 0.46)
                .scaledBy(x: 0.24, y: 0.24)
            self.floatGroup.alpha = 0
            self.cancelButton.alpha = 0
            self.releaseButton.alpha = 0
        } completion: { _ in
            self.onRelease?(text)
            self.dismiss(animated: false)
        }
        Breadcrumbs.log("p91 wish fly")
    }
}
