import UIKit

/// port90（任务 22）：日记本页（样片 #diary 定版形态）——全屏
/// 纸面页自底部升起：头部（返回＋「日记本」＋今日日期）、
/// 「贴进日记本的歌」列表、「写今天的日记」（可选挂歌＋横线
/// 纸文本＋涂鸦画板＋保存）、「日记墙」（条目卡：胶带条＋
/// 挂歌行＋文字＋画作＋时间）。数据走 DiaryStore90 单源。
final class DiaryViewController90: UIViewController {

    private var taggedSong: DiarySong90?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let songsStack = UIStackView()
    private let tagChip = UIView()
    private let tagLabel = UILabel()
    private var tagSong: DiarySong90?
    private let textView = DiaryTextView90()
    private let pad = DrawPad90()
    private let entriesStack = UIStackView()

    init(tagged track: FoliaTrack?) {
        if let track { taggedSong = DiarySong90(track: track) }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let paper = UIColor(red: 0.96, green: 0.93, blue: 0.88, alpha: 1)
    private static let ink = UIColor(red: 0.18, green: 0.16, blue: 0.13, alpha: 1)
    private static let dim = UIColor(red: 0.55, green: 0.52, blue: 0.44, alpha: 1)
    private static let card = UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.paper
        build()
        tagSong = taggedSong
        reload()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: .foliaDiary90Changed, object: nil)
        Breadcrumbs.log("port90 diary open tagged=\(taggedSong != nil ? 1 : 0)")
    }

    private func build() {
        // 头部
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = UIButton(type: .system)
        back.setImage(UIImage(systemName: "chevron.left",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal)
        back.tintColor = Self.ink
        back.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(back)
        let title = UILabel()
        title.text = "日记本"
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        title.textColor = Self.ink
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        let dateLabel = UILabel()
        dateLabel.text = Self.todayText()
        dateLabel.font = .systemFont(ofSize: 11.5)
        dateLabel.textColor = Self.dim
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(dateLabel)
        let divider = UIView()
        divider.backgroundColor = UIColor.black.withAlphaComponent(0.10)
        divider.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(divider)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 64),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 44),
            title.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 2),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            dateLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        stack.addArrangedSubview(sectionHeader("贴进日记本的歌"))
        songsStack.axis = .vertical
        songsStack.spacing = 8
        stack.addArrangedSubview(songsStack)

        stack.addArrangedSubview(sectionHeader("写今天的日记"))
        buildForm()

        stack.addArrangedSubview(sectionHeader("日记墙"))
        entriesStack.axis = .vertical
        entriesStack.spacing = 14
        stack.addArrangedSubview(entriesStack)
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor(red: 0.43, green: 0.39, blue: 0.31, alpha: 1)
        return label
    }

    private func buildForm() {
        // 挂歌条（从拍立得小钮进来时预挂，可清除）
        tagChip.backgroundColor = UIColor(red: 1, green: 0.95, blue: 0.84, alpha: 1)
        tagChip.layer.cornerRadius = 12
        tagChip.layer.borderWidth = 1
        tagChip.layer.borderColor = UIColor(red: 0.75, green: 0.55, blue: 0.16, alpha: 0.3).cgColor
        tagChip.isHidden = true
        let tagStack = UIStackView()
        tagStack.axis = .horizontal
        tagStack.alignment = .center
        tagStack.spacing = 9
        tagStack.translatesAutoresizingMaskIntoConstraints = false
        tagChip.addSubview(tagStack)
        tagLabel.font = .systemFont(ofSize: 12.5)
        tagLabel.textColor = UIColor(red: 0.48, green: 0.36, blue: 0.08, alpha: 1)
        tagLabel.lineBreakMode = .byTruncatingTail
        let tagClear = UIButton(type: .system)
        tagClear.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)),
            for: .normal)
        tagClear.tintColor = UIColor(red: 0.65, green: 0.51, blue: 0.18, alpha: 1)
        tagClear.addTarget(self, action: #selector(clearTag), for: .touchUpInside)
        tagStack.addArrangedSubview(tagLabel)
        tagStack.addArrangedSubview(tagClear)
        NSLayoutConstraint.activate([
            tagStack.topAnchor.constraint(equalTo: tagChip.topAnchor, constant: 9),
            tagStack.bottomAnchor.constraint(equalTo: tagChip.bottomAnchor, constant: -9),
            tagStack.leadingAnchor.constraint(equalTo: tagChip.leadingAnchor, constant: 12),
            tagStack.trailingAnchor.constraint(equalTo: tagChip.trailingAnchor, constant: -8),
        ])
        stack.addArrangedSubview(tagChip)

        textView.font = .systemFont(ofSize: 14.5)
        textView.textColor = Self.ink
        textView.backgroundColor = Self.card
        textView.layer.cornerRadius = 12
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.black.withAlphaComponent(0.10).cgColor
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 13, bottom: 9, right: 13)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        stack.addArrangedSubview(textView)

        // 画板卡：标签＋画布＋工具行（色板/粗细/撤销/清空）
        let drawCard = UIView()
        drawCard.backgroundColor = Self.card
        drawCard.layer.cornerRadius = 12
        drawCard.layer.borderWidth = 1
        drawCard.layer.borderColor = UIColor.black.withAlphaComponent(0.10).cgColor
        let drawLabel = UILabel()
        drawLabel.text = "画一画"
        drawLabel.font = .systemFont(ofSize: 11.5)
        drawLabel.textColor = Self.dim
        drawLabel.translatesAutoresizingMaskIntoConstraints = false
        drawCard.addSubview(drawLabel)
        pad.translatesAutoresizingMaskIntoConstraints = false
        drawCard.addSubview(pad)
        let tools = UIStackView()
        tools.axis = .horizontal
        tools.alignment = .center
        tools.spacing = 7
        tools.translatesAutoresizingMaskIntoConstraints = false
        drawCard.addSubview(tools)
        let colors: [UIColor] = [
            UIColor(red: 0.18, green: 0.16, blue: 0.13, alpha: 1),
            UIColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 1),
            UIColor(red: 0.95, green: 0.62, blue: 0.16, alpha: 1),
            UIColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1),
            UIColor(red: 0.35, green: 0.68, blue: 0.40, alpha: 1),
            UIColor(red: 0.60, green: 0.40, blue: 0.75, alpha: 1),
        ]
        for (index, color) in colors.enumerated() {
            let swatch = UIButton(type: .custom)
            swatch.backgroundColor = color
            swatch.layer.cornerRadius = 15
            swatch.layer.borderWidth = index == 0 ? 2.5 : 1
            swatch.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
            swatch.tag = index
            swatch.addTarget(self, action: #selector(colorPicked(_:)), for: .touchUpInside)
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.widthAnchor.constraint(equalToConstant: 30).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 30).isActive = true
            swatch.accessibilityLabel = "画笔颜色"
            tools.addArrangedSubview(swatch)
            if index == 0 { pad.currentColor = color }
        }
        for (label, action) in [("细", #selector(sizeThin)), ("粗", #selector(sizeThick)),
                                ("撤销", #selector(padUndo)), ("清空", #selector(padClear))] {
            let tool = UIButton(type: .system)
            tool.setTitle(label, for: .normal)
            tool.titleLabel?.font = .systemFont(ofSize: 12)
            tool.setTitleColor(UIColor(red: 0.36, green: 0.33, blue: 0.27, alpha: 1), for: .normal)
            tool.backgroundColor = UIColor.black.withAlphaComponent(0.06)
            tool.layer.cornerRadius = 18
            tool.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            tool.addTarget(self, action: action, for: .touchUpInside)
            tool.translatesAutoresizingMaskIntoConstraints = false
            tool.heightAnchor.constraint(equalToConstant: 36).isActive = true
            tools.addArrangedSubview(tool)
        }
        NSLayoutConstraint.activate([
            drawLabel.topAnchor.constraint(equalTo: drawCard.topAnchor, constant: 9),
            drawLabel.leadingAnchor.constraint(equalTo: drawCard.leadingAnchor, constant: 12),
            pad.topAnchor.constraint(equalTo: drawLabel.bottomAnchor, constant: 4),
            pad.leadingAnchor.constraint(equalTo: drawCard.leadingAnchor),
            pad.trailingAnchor.constraint(equalTo: drawCard.trailingAnchor),
            pad.heightAnchor.constraint(equalToConstant: 170),
            tools.topAnchor.constraint(equalTo: pad.bottomAnchor, constant: 6),
            tools.leadingAnchor.constraint(equalTo: drawCard.leadingAnchor, constant: 10),
            tools.trailingAnchor.constraint(lessThanOrEqualTo: drawCard.trailingAnchor, constant: -10),
            tools.bottomAnchor.constraint(equalTo: drawCard.bottomAnchor, constant: -9),
        ])
        stack.addArrangedSubview(drawCard)

        let save = UIButton(type: .system)
        save.setTitle("贴进日记本", for: .normal)
        save.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        save.setTitleColor(UIColor(red: 0.97, green: 0.95, blue: 0.89, alpha: 1), for: .normal)
        save.backgroundColor = Self.ink
        save.layer.cornerRadius = 14
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        save.translatesAutoresizingMaskIntoConstraints = false
        save.heightAnchor.constraint(equalToConstant: 50).isActive = true
        stack.addArrangedSubview(save)
    }

    // MARK: 数据回刷

    @objc private func reload() {
        // 歌曲区
        for sub in songsStack.arrangedSubviews { songsStack.removeArrangedSubview(sub); sub.removeFromSuperview() }
        let songs = DiaryStore90.songs
        if songs.isEmpty {
            let none = UILabel()
            none.text = "还没有贴进来的歌。在封面或拍立得上点 ➕ 就能贴进来。"
            none.font = .systemFont(ofSize: 12.5)
            none.textColor = UIColor(red: 0.63, green: 0.60, blue: 0.50, alpha: 1)
            none.numberOfLines = 0
            songsStack.addArrangedSubview(none)
        } else {
            for song in songs { songsStack.addArrangedSubview(songRow(song)) }
        }
        // 挂歌条
        if let tag = tagSong {
            tagChip.isHidden = false
            tagLabel.text = "\(tag.title) · \(tag.artist)"
        } else {
            tagChip.isHidden = true
        }
        // 日记墙
        for sub in entriesStack.arrangedSubviews { entriesStack.removeArrangedSubview(sub); sub.removeFromSuperview() }
        let entries = DiaryStore90.entries
        if entries.isEmpty {
            let none = UILabel()
            none.text = "日记墙还空着，写下第一篇吧。"
            none.font = .systemFont(ofSize: 12.5)
            none.textColor = UIColor(red: 0.63, green: 0.60, blue: 0.50, alpha: 1)
            entriesStack.addArrangedSubview(none)
        } else {
            for entry in entries { entriesStack.addArrangedSubview(entryCard(entry)) }
        }
    }

    private func songRow(_ song: DiarySong90) -> UIView {
        let row = UIView()
        row.backgroundColor = Self.card
        row.layer.cornerRadius = 12
        row.layer.borderWidth = 1
        row.layer.borderColor = UIColor.black.withAlphaComponent(0.07).cgColor
        let cover = UIImageView()
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 8
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        cover.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(cover)
        loadCover90(cover, raw: song.artwork, id: song.id)
        let title = UILabel()
        title.text = song.title
        title.font = .systemFont(ofSize: 13.5, weight: .semibold)
        title.textColor = Self.ink
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(title)
        let artist = UILabel()
        artist.text = song.artist
        artist.font = .systemFont(ofSize: 11.5)
        artist.textColor = Self.dim
        artist.lineBreakMode = .byTruncatingTail
        artist.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(artist)
        let use = UIButton(type: .system)
        use.setTitle("写日记", for: .normal)
        use.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        use.setTitleColor(UIColor(red: 0.48, green: 0.36, blue: 0.08, alpha: 1), for: .normal)
        use.addTarget(self, action: #selector(useSong(_:)), for: .touchUpInside)
        use.accessibilityHint = song.id
        use.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(use)
        let remove = UIButton(type: .system)
        remove.setImage(UIImage(systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)),
            for: .normal)
        remove.tintColor = UIColor(red: 0.70, green: 0.66, blue: 0.57, alpha: 1)
        remove.addTarget(self, action: #selector(removeSong(_:)), for: .touchUpInside)
        remove.accessibilityHint = song.id
        remove.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(remove)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 7),
            cover.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
            cover.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -7),
            cover.widthAnchor.constraint(equalToConstant: 38),
            cover.heightAnchor.constraint(equalToConstant: 38),
            title.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 10),
            title.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
            title.trailingAnchor.constraint(equalTo: use.leadingAnchor, constant: -6),
            artist.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            artist.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            artist.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            use.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            use.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -2),
            remove.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            remove.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            remove.widthAnchor.constraint(equalToConstant: 36),
            remove.heightAnchor.constraint(equalToConstant: 36),
        ])
        return row
    }

    private func entryCard(_ entry: DiaryEntry90) -> UIView {
        let cardView = UIView()
        cardView.backgroundColor = Self.card
        cardView.layer.cornerRadius = 6
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = UIColor.black.withAlphaComponent(0.07).cgColor
        cardView.layer.shadowColor = UIColor(red: 0.31, green: 0.26, blue: 0.16, alpha: 1).cgColor
        cardView.layer.shadowOpacity = 0.10
        cardView.layer.shadowRadius = 7
        cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 8
        inner.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            inner.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
        ])
        // 胶带条
        let tape = UIView()
        tape.backgroundColor = UIColor(red: 0.94, green: 0.86, blue: 0.63, alpha: 0.75)
        tape.transform = CGAffineTransform(rotationAngle: -2 * .pi / 180)
        tape.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(tape)
        NSLayoutConstraint.activate([
            tape.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            tape.topAnchor.constraint(equalTo: cardView.topAnchor, constant: -8),
            tape.widthAnchor.constraint(equalToConstant: 86),
            tape.heightAnchor.constraint(equalToConstant: 18),
        ])
        if let songTitle = entry.songTitle {
            let songLabel = UILabel()
            songLabel.text = "♪ \(songTitle)\(entry.songArtist.map { " · \($0)" } ?? "")"
            songLabel.font = .systemFont(ofSize: 12, weight: .medium)
            songLabel.textColor = UIColor(red: 0.48, green: 0.36, blue: 0.08, alpha: 1)
            songLabel.lineBreakMode = .byTruncatingTail
            inner.addArrangedSubview(songLabel)
        }
        if !entry.text.isEmpty {
            let body = UILabel()
            body.text = entry.text
            body.font = .systemFont(ofSize: 14)
            body.textColor = Self.ink
            body.numberOfLines = 0
            inner.addArrangedSubview(body)
        }
        if let url = DiaryStore90.sketchURL(for: entry),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            let sketch = UIImageView(image: image)
            sketch.contentMode = .scaleAspectFit
            sketch.backgroundColor = .white
            sketch.layer.cornerRadius = 8
            sketch.layer.borderWidth = 1
            sketch.layer.borderColor = UIColor.black.withAlphaComponent(0.08).cgColor
            sketch.clipsToBounds = true
            sketch.translatesAutoresizingMaskIntoConstraints = false
            sketch.heightAnchor.constraint(equalToConstant: 170).isActive = true
            inner.addArrangedSubview(sketch)
        }
        let time = UILabel()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 HH:mm"
        time.text = f.string(from: Date(timeIntervalSince1970: entry.createdAt))
        time.font = .systemFont(ofSize: 11)
        time.textColor = UIColor(red: 0.63, green: 0.60, blue: 0.50, alpha: 1)
        inner.addArrangedSubview(time)
        return cardView
    }

    private func loadCover90(_ imageView: UIImageView, raw: String?, id: String) {
        guard let raw else { return }
        let loader = NativeCoverLoader.shared
        let proxy = loader.proxiedURLString(raw, tier: 256)
        if let key = proxy, let cached = loader.cachedImage(for: key) {
            imageView.image = cached
            return
        }
        if let cached = loader.cachedImageAnyTier(raw: raw, excludingTier: 256) {
            imageView.image = cached
            return
        }
        Task { [weak imageView] in
            let image = await loader.image(for: proxy ?? raw, tier: 256)
            guard let imageView, let image else { return }
            imageView.image = image
        }
    }

    // MARK: 动作

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func clearTag() { tagSong = nil; reload() }

    @objc private func useSong(_ sender: UIButton) {
        guard let id = sender.accessibilityHint,
              let song = DiaryStore90.songs.first(where: { $0.id == id }) else { return }
        tagSong = song
        reload()
        textView.becomeFirstResponder()
    }

    @objc private func removeSong(_ sender: UIButton) {
        guard let id = sender.accessibilityHint else { return }
        if tagSong?.id == id { tagSong = nil }
        DiaryStore90.removeSong(id: id)
    }

    @objc private func colorPicked(_ sender: UIButton) {
        pad.currentColor = sender.backgroundColor ?? Self.ink
        for sub in sender.superview?.subviews ?? [] {
            (sub as? UIButton)?.layer.borderWidth = sub == sender ? 2.5 : 1
        }
    }

    @objc private func sizeThin() { pad.currentWidth = 2.5 }
    @objc private func sizeThick() { pad.currentWidth = 6 }
    @objc private func padUndo() { pad.undo() }
    @objc private func padClear() { pad.clear() }

    @objc private func saveTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sketch = pad.isEmpty ? nil : pad.renderPNG()
        guard !text.isEmpty || tagSong != nil || sketch != nil else { return }
        DiaryStore90.addEntry(text: text, song: tagSong, sketchPNG: sketch)
        textView.text = ""
        pad.clear()
        tagSong = nil
        reload()
        Breadcrumbs.log("port90 diary save text=\(text.count) sketch=\(sketch != nil ? 1 : 0)")
    }

    private static func todayText() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 · EEEE"
        return f.string(from: Date())
    }
}

/// 横线纸文本框：行距 28 与底纹横线对齐（样片 #dText 同式）。
final class DiaryTextView90: UITextView {
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor(red: 0.35, green: 0.43, blue: 0.63, alpha: 0.14).cgColor)
        ctx.setLineWidth(1)
        var y: CGFloat = 9 + 28
        while y < rect.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
            y += 28
        }
        ctx.strokePath()
    }
}

/// 涂鸦画板：多笔划（颜色/粗细/点列）逐笔重绘；可撤销/清空/
/// 导出 PNG。触摸在画布内拦截，不与外层滚动冲突（画板区
/// 禁用祖先滚动手势的穿透由 UIScrollView 默认延迟决定，
/// 真机验证点已登记报告）。
final class DrawPad90: UIView {

    struct Stroke {
        var color: UIColor
        var width: CGFloat
        var points: [CGPoint]
    }

    private(set) var strokes: [Stroke] = []
    private var current: Stroke?
    var currentColor: UIColor = .black
    var currentWidth: CGFloat = 2.5
    var isEmpty: Bool { strokes.isEmpty && current == nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 绘画期间锁住祖先滚动（否则画笔拖动会被日记页滚动抢走）。
    private func setAncestorScrollEnabled(_ enabled: Bool) {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                scroll.isScrollEnabled = enabled
                return
            }
            ancestor = view.superview
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        setAncestorScrollEnabled(false)
        current = Stroke(color: currentColor, width: currentWidth, points: [point])
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self), current != nil else { return }
        current?.points.append(point)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let done = current { strokes.append(done) }
        current = nil
        setAncestorScrollEnabled(true)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        for stroke in strokes + (current.map { [$0] } ?? []) {
            drawStroke(stroke, in: ctx)
        }
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        ctx.setStrokeColor(stroke.color.cgColor)
        ctx.setLineWidth(stroke.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        guard let first = stroke.points.first else { return }
        if stroke.points.count == 1 {
            ctx.move(to: first)
            ctx.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
        } else {
            ctx.move(to: first)
            for point in stroke.points.dropFirst() { ctx.addLine(to: point) }
        }
        ctx.strokePath()
    }

    func undo() {
        _ = strokes.popLast()
        setNeedsDisplay()
    }

    func clear() {
        strokes.removeAll()
        current = nil
        setNeedsDisplay()
    }

    func renderPNG() -> Data? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(bounds)
            if let ctx = UIGraphicsGetCurrentContext() {
                for stroke in strokes { drawStroke(stroke, in: ctx) }
            }
        }
        return image.pngData()
    }
}
