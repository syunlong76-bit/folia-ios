import UIKit

// 灵动岛宠物层（3.7 (32)，Miller 2026-11-20 01:05 定案的障眼
// 法版 + 01:55 三地流转）：宠物不进真灵动岛（Live Activity
// 不给逐帧动画）——墙台宠物说完告别词后分流至此，沿屏幕往
// 上蹦到灵动岛位置落座；灵动岛由系统渲染、恒在本层之上，
// 宠物下半身被岛的黑框天然遮住、上半身露出，像坐在岛里。
//
// 承载：3.7 (39) 改挂主窗根视图顶层（单窗）——独立
// UIWindow 形态经 (36)/(37)/(38) 三轮真机二分定案为冻死
// 充分条件（与 level、岛上内容无关），障眼法几何只依赖
// 屏幕坐标、不依赖独立窗口，故取消建窗。
// 3.7 (41) 组1（审计 folia40-failures A1 定案）：(39) 的根
// 视图宿主被呈现栈整体盖住——主页/曲目墙/舞台/设置页全是
// 一层层 present 上去的，被 present 的视图恒在根视图之上，
// install 时那一次 bringSubviewToFront 对呈现栈无效，宠物
// 爬升/落座/停聊全程在被盖住的层里空跑（日志机制全活、
// Miller 从未看见）。改挂**主窗本体**的顶层子视图（仍是同
// 一个窗的子视图，不新建独立 UIWindow，不碰 (39) 冻案红
// 线），并设 0.5s 置顶守护：任一呈现/散场后窗口子视图顺序
// 有变，下一拍即把本层重新置顶；呈现完成时刻另有事件驱动
// 的即时置顶（install/激活/收宠物）。墙↔舞台↔主页之间导
// 航时不消失、不重建。hitTest 只认领宠物本体，其余全穿
// 透。仅 App 前台有效；横屏时岛位不在顶部，本层保守隐藏
// 宠物（状态保留，回竖屏恢复）。
//
// 几何（iPhone 14 Pro 竖屏，窗口坐标）：岛黑框约宽 126、
// 高 37、顶距屏幕上沿约 11pt。
// 落座口径（3.7 (44) 改回岛中）：宠物 46pt、脚底 y=45，帧
// y∈[−1,45]——宠物坐在岛「中」，头顶露在岛上沿之上、身
// 体藏于系统胶囊黑框之后（障眼法本义）。沿革：(41) 此口
// 径真机只露头顶约 24%（岛上沿距屏顶仅 11pt，上方可见量
// 有硬上限，审计 folia43 路1 定案）；(43) 曾翻案「下沿出
// 岛」（50pt、脚底 93、约 90% 身体垂在岛下），Miller 真
// 机判突兀，(44) 拍板改回岛中——几何上限是已知取舍，不
// 再翻案。落座站位：双只 [−40,+40]、单只居中（(53) M
// 固定双人组口径，三只表随容量 3 退役，详见文末 M 段）。
// 落座后常驻闲晃（小幅位移）、
// 偶尔冒「到家库」气泡；居民 ≥2 只时按人格停聊（随机抽
// 对，轮流冒泡）。点岛上宠物 → 蹦回当前最前点播台（舞台
// 优先，其次墙台）；被墙台召回时经
// PetHomeRegistry.onIslandDeparture 撤下。
//
// 已知边界：岛被系统事件（来电/Face ID 等）展开时无公开
// 信号可测，宠物落点会短暂错位，事件结束岛恢复原尺寸后
// 宠物仍在原座位（不穿帮成悬空——宠物始终贴在岛原几何上）。
//
// (53) 工作流 G（DS 终审 island-final-reply2 路线 c 定版）：
// ① 挂载：(41) 的「主窗子视图 + zPosition=1000」在 (50) 仍
// 被全屏 presented VC 盖住——机制是 zPosition 只在同一
// superlayer 的兄弟间竞争：宠物层挂在根视图层树内时，它与
// presented 容器的竞争发生在父级（根视图层 vs 呈现容器层），
// 子层 z 再高也抬不出父级。本版改 graft：本层 layer 本体
// （petRootLayer）直接 addSublayer 到 window.layer，与根视
// 图层/呈现容器层同为 window.layer 直属子层，zPosition=
// 10000 在这一级竞争、恒压其上；本层视图本体与宠物视图都
// 不再进入任何窗口视图树（superview 恒 nil），不新建
// UIWindow（(39) 冻案红线不变）。0.5s 守护改职：不再
// bringSubviewToFront 本层，改为核 graft 是否仍直属
// window.layer + z 恒定 + 窗 bounds 同步 + proxy 序位。
// ② 触摸：CALayer 不进 hitTest 链，点按改由唯一窗口子视图
// PetHitProxyView 承接（frame 只覆盖顶部 seat+气泡带，
// point(inside:) 逐宠矩形判定、其余穿透），命中后转发回
// 本层 islandPetTapped/islandPetDoubleTapped，行为不变。
// ③ APNG 存续核查（实查 APNGSticker.swift）：StickerView
// 自有 CADisplayLink 有两处 window 门控——startLinkIfNeeded
// 有 guard window != nil、didMoveToWindow 在 window==nil 时
// 暂停 link。宠物脱离视图树后 window 恒 nil，自有 link 永
// 不启动、动画会冻在 restart() 摆出的第一帧（tick 本体只读
// isHidden/alpha/decoded，不依赖 window）。最小适配 = 岛层
// 统一驱动：本层自持一条 CADisplayLink，逐帧对在座宠物与
// 反应贴纸的 StickerView 调其 tick(_:)（@objc 运行时转发，
// APNGSticker.swift 不在本工作流文件归属内、不动它）。
// ④ 已知连带：PetDockLayer 的守护以 island.superview ===
// window 判岛层在场——本版岛层不再是子视图，它自动走自置
// 顶退化分支（其 z=999 仍压呈现内容，功能不回退）；停靠层
// 本身不在本工作流范围，未动。
//
// (53) 工作流 M（Miller 2026-11-21 截图点名）：岛居民由
// (43) 的随机轮换选角（容量 3／两猫一狗／活泼优先分流）
// 改为固定双人组——捂脸猫 cat-live（歌单加载页拍立得底部
// 定版同只，APNG 60 帧原帧、岛层统一驱动照旧推进）+ 爱
// 心狗 dog-11（抱大红爱心，贴纸包内唯一抱爱心者；双狗抱
// 抱的 dog-10 无爱心、落选）。选角数据源在 PetHome
// Registry.islandFixedDuo（写入 .island 时非双人组改道回
// 池），本层 seatPet 再设一道同口径闸兜底，两处不打架。
// 容量语义随之 3→2；站位只剩双只 [−40,+40]（按双人组序
// 猫左狗右）与单只居中（一只被召回/尚未到岛的过渡态）。
// 落座几何（46pt／脚底 45）、上岛路径、闲晃冒泡、点按
// 回台、岛聊抽对（双人之间聊）与 G 的 graft／proxy／统
// 一驱动结构全部不动。汪汪队开大会（工作流 J）撤下走登
// 记表 setHome(.pool) 的既有 onIslandDeparture 回调、恢
// 复走墙台告别分流的既有落座路——恢复回来的仍是这对
// （非双人组到不了岛），岛侧无需新钩子。

private final class IslandPetView: UIView {
    let stickerView = StickerView()
    let asset: String
    var personality: PetPersonality { PetPersonalities.of(asset) }
    /// 落座基准点（脚底中心），闲晃在其周围小幅漂移。
    var seatFeet = CGPoint.zero
    weak var islandLayer: PetIslandLayer?

    init(asset: String, size: CGFloat) {
        self.asset = asset
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        stickerView.frame = bounds
        stickerView.crumbScene = "island-pet"
        stickerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(stickerView)
        stickerView.setSticker(asset, mode: .loop)
        // (53) G：本视图不再进任何视图树，自带手势识别器永无
        // 触摸可收——已删。点按统一由 PetHitProxyView 命中后
        // 经岛层 proxyTapped 转发到 islandPetTapped /
        // islandPetDoubleTapped。
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    var feetY: CGFloat {
        get { center.y + bounds.height / 2 }
        set { center.y = newValue - bounds.height / 2 }
    }
}

final class PetIslandLayer: UIView {

    static let shared = PetIslandLayer()

    private static let petSize: CGFloat = 46
    /// 脚底线（3.7 (44) 改回岛中，(41) 口径）：脚底 45、帧
    /// y∈[−1,45]，宠物坐进岛里（头顶露上沿、身体藏胶囊
    /// 后）。(43) 的 93（下沿出岛）真机被判突兀已回退，勿
    /// 按 (43) 口径调；落座几何不随 (53) M 的居民改定动
    /// （容量/站位/选角的 M 口径见文件头文末 M 段）。
    private static let seatFeetY: CGFloat = 45
    /// petRootLayer 的 zPosition（(53) G，DS 终审路线 c）：
    /// 与 window.layer 的其它直属子层（根视图层/呈现容器层）
    /// 同级竞争，10000 恒压其上。停靠层的 999 是窗口子视图
    /// 层级内的序，与本值不在同一棵层树、不冲突。
    private static let petRootZPosition: CGFloat = 10_000
    /// proxy 覆盖带高度：seat 区（帧顶 −1…脚底 45）+ 气泡
    /// （pet maxY+4 起、高 26，底 ≈75）+ 闲晃/小跳余量，120
    /// 只占屏幕顶带。
    private static let proxyZoneHeight: CGFloat = 120

    private var pets: [IslandPetView] = []
    private var tickTimer: Timer?
    /// 宿主主窗（(53) G）：本层视图本体不再进窗，petRootLayer
    /// （= 本层 layer）直挂它的 layer；hostWindow 只作 graft
    /// 与 proxy 的锚。scene 重连换新窗时 install 重新 graft。
    private weak var hostWindow: UIWindow?
    /// graft 本体：本层 layer 即 DS 定名的 petRootLayer，宠物
    /// 子视图的 layer 经 addSubview 自然挂在它之下。
    private var petRootLayer: CALayer { layer }
    /// 命中代理（(53) G）：岛层在窗口里的唯一子视图，frame
    /// 只覆盖顶部 seat+气泡带，点按经它转发回本层。
    private var hitProxy: PetHitProxyView?
    /// APNG 岛层统一驱动（(53) G③）：StickerView 自有
    /// CADisplayLink 被 window 门控（结论见文件头），本 link
    /// 逐帧调其 tick(_:) 推进帧；无宠物且无反应贴纸时停。
    private var stickerDriveLink: CADisplayLink?
    /// 当前气泡的属主宠物 asset（proxy 命中气泡时按属主转发）。
    private var bubbleOwnerAsset: String?
    /// 守护（(53) G 改职）：0.5s 一拍核 graft 直属关系、z 恒
    /// 定、窗 bounds 同步与 proxy 序位，失守即修复并落
    /// island.refront（不再对本层 bringSubviewToFront）。
    private var refrontTimer: Timer?
    /// 层序面包屑去重签名（3.7 (46)）：island.layer.state 只在
    /// 序位/上方邻居变化时落盘，防 0.5s 守护拍刷屏。
    private var lastLayerStateSignature = ""
    private var nextBubbleAt: TimeInterval = 0
    private var nextChatAt: TimeInterval = 0
    private var chatLines: [(pet: IslandPetView, text: String)] = []
    private var chatLineIndex = -1
    private var chatLineUntil: TimeInterval = 0
    private var bubbleLabel: UILabel?
    private var bubbleUntil: TimeInterval = 0
    private var reactionView: StickerView?

    private init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        // (53) G：本视图永不进视图树，交互恒关（触摸归 proxy）；
        // 防御性关闭，避免将来误入视图树时整屏吃触摸。
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: 安装（SceneDelegate 建窗后一行）

    static func install(in windowScene: UIWindowScene) {
        let layer = PetIslandLayer.shared
        // 宿主窗（SceneDelegate 的 window 优先，key window 兜
        // 底）。(53) G：graft 不直属当前窗 layer（首装/scene
        // 重连换新窗）就重新 graft；落座几何口径不变。
        let hostWindow = (windowScene.delegate as? SceneDelegate)?.window
            ?? windowScene.windows.first(where: { $0.isKeyWindow })
            ?? windowScene.windows.first
        guard let window = hostWindow else {
            Breadcrumbs.log("island.install skipped=no-host")
            return
        }
        if layer.petRootLayer.superlayer !== window.layer
            || layer.hostWindow !== window {
            // 旧 graft 先摘（换窗时旧窗 layer 随窗消亡，此处只
            // 是把引用摘干净），新窗重新直挂：petRootLayer 作
            // 为 window.layer 直属子层、z=10000——与根视图层/
            // 呈现容器层同级竞争，(46) 的 z=1000 输在父级、
            // 本版赢在同级（机制见文件头 (53) G①）。
            layer.petRootLayer.removeFromSuperlayer()
            layer.frame = window.bounds
            layer.petRootLayer.zPosition = Self.petRootZPosition
            window.layer.addSublayer(layer.petRootLayer)
            layer.hostWindow = window
            layer.installProxy(in: window)
            Breadcrumbs.log("island.install host=window.layer"
                + " z=\(Int(Self.petRootZPosition))"
                + " resident=fixedDuo"
                + " duo=\(PetHomeRegistry.islandFixedDuo.joined(separator: ","))"
                + " residents=\(PetHomeRegistry.shared.islandResidents.count)")
            layer.logLayerState(reason: "install")
            PetHomeRegistry.shared.onIslandDeparture = { [weak layer] asset in
                layer?.releasePet(asset: asset)
            }
        }
        layer.startRefrontGuard()
        // 冷启动时登记表为空；若已有岛民（重连场景）补落座。
        for asset in PetHomeRegistry.shared.islandResidents
        where !layer.pets.contains(where: { $0.asset == asset }) {
            layer.seatPet(asset: asset, animated: false, fromRect: nil)
        }
        layer.updateVisibility()
        layer.syncProxyState()
    }

    /// proxy 安装（(53) G）：唯一窗口子视图，原点 (0,0)、只
    /// 覆盖顶部 seat+气泡带；置于窗口子视图最上（hitTest 只
    /// 认 subviews 序、不认 zPosition，proxy 必须在呈现容器
    /// 之上才有机会先判定——它逐矩形判定、空白穿透，置顶
    /// 不拦任何内容触摸）。
    private func installProxy(in window: UIWindow) {
        let proxy = hitProxy ?? PetHitProxyView()
        hitProxy = proxy
        proxy.islandLayer = self
        if proxy.superview !== window {
            proxy.removeFromSuperview()
            window.addSubview(proxy)
        }
        proxy.frame = Self.proxyFrame(windowWidth: window.bounds.width)
        window.bringSubviewToFront(proxy)
    }

    private static func proxyFrame(windowWidth: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: windowWidth, height: proxyZoneHeight)
    }

    // MARK: graft 守护（(53) G 改职，原 (41) 置顶守护）

    /// 启动守护（幂等）：0.5s 一拍（.common 模式，转场/滚动
    /// 期间照常走）。渲染层序已由 zPosition=10000 在
    /// window.layer 同级锁死、不依赖本守护；守护只兜三件
    /// 事：graft 被摘/ z 被改时修复、窗 bounds 变化时几何同
    /// 步、proxy 被呈现容器压到下面时提回顶。
    private func startRefrontGuard() {
        guard refrontTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refrontIfNeeded(logged: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        refrontTimer = timer
    }

    /// 即时守护（事件驱动入口：SceneDelegate 激活、收宠物
    /// 时调用）：守护拍之间的变化不等下一拍。方法名沿用
    /// (41)（SceneDelegate 调用点不改），语义已换成 graft 守护。
    func refrontIfNeeded() {
        refrontIfNeeded(logged: false)
    }

    private func refrontIfNeeded(logged: Bool) {
        // (58) 掉帧量测：本守护是嫌疑#3（入场期被 SceneDelegate
        // 反复触发），整段耗时登记进 EntryCallbackTimings，
        // 入场 teardown 汇总 top3 与 >50ms 帧间隔对位。
        let timingStart = CACurrentMediaTime()
        defer {
            EntryCallbackTimings.record(
                "island.refront",
                ms: (CACurrentMediaTime() - timingStart) * 1000)
        }
        guard let window = hostWindow else { return }
        var repaired = false
        // ① graft 守护：petRootLayer 必须仍直属 window.layer
        // 且 z 恒定（UIKit 不会主动摘应用自加的子层，此为换
        // 窗/异常兜底；真被摘时下一拍即复位）。
        if petRootLayer.superlayer !== window.layer {
            window.layer.addSublayer(petRootLayer)
            repaired = true
        }
        if petRootLayer.zPosition != Self.petRootZPosition {
            petRootLayer.zPosition = Self.petRootZPosition
            repaired = true
        }
        // ② 几何同步：无 autoresizing 可依（本层不在视图树），
        // 窗 bounds 变（旋转/分屏）时手动跟随并重落座。
        if frame != window.bounds {
            frame = window.bounds
            layoutIfNeeded()
            reseatAll(animated: false)
            updateVisibility()
            hitProxy?.frame = Self.proxyFrame(windowWidth: window.bounds.width)
            repaired = true
        }
        // ③ proxy 序位：hitTest 不认 zPosition、只认 subviews
        // 序，proxy 须在呈现容器之上才有判定机会。停靠层在
        // 最上方视为在位——它只认领自家宠物、其余穿透，与
        // proxy 互不遮挡，避免两层守护互相抢置顶对打。
        if let proxy = hitProxy {
            if proxy.superview !== window {
                window.addSubview(proxy)
                repaired = true
            }
            let top = window.subviews.last
            if top !== proxy && top !== PetDockLayer.shared {
                window.bringSubviewToFront(proxy)
                repaired = true
            }
        }
        if repaired {
            if logged { Breadcrumbs.log("island.refront") }
            logLayerState(reason: "refront")
        }
    }

    /// 层序判读面包屑（(53) G 续 (46) 族）：宿主口径换成
    /// window.layer——graft 是否直属、z、proxy 序位、居民数。
    /// 真机再报「宠物在底层」时凭此一行定位：grafted=0 = graft
    /// 被摘；grafted=1 且 z=10000 仍被盖 = 对方不在本窗
    /// window.layer 树内（独立窗/系统层），非本路线可及。
    /// 签名变化才落盘，防 0.5s 守护拍刷屏。
    func logLayerState(reason: String) {
        guard let window = hostWindow else { return }
        let grafted = petRootLayer.superlayer === window.layer
        let proxyState: String
        if hitProxy == nil { proxyState = "none" }
        else if window.subviews.last === hitProxy { proxyState = "front" }
        else { proxyState = "back" }
        let signature = "\(grafted)/\(petRootLayer.zPosition)/\(proxyState)/\(pets.count)"
        guard reason == "install" || reason == "seat"
                || signature != lastLayerStateSignature else { return }
        lastLayerStateSignature = signature
        Breadcrumbs.log("island.layer.state reason=\(reason) host=window.layer"
            + " grafted=\(grafted ? 1 : 0) z=\(petRootLayer.zPosition)"
            + " proxy=\(proxyState) pets=\(pets.count)")
    }

    // MARK: 触摸（(53) G：唯一 PetHitProxyView 转发）

    /// proxy 的命中目标（窗口坐标 == 本层坐标：petRootLayer
    /// frame = window.bounds、原点同为 (0,0)）：在座宠物本体
    /// + 当前气泡。气泡后入列，proxy 逆序查、重叠时气泡优先。
    /// 横屏宠物隐藏期间返回空（proxy 整体停用同效）。
    func hitTargets() -> [(rect: CGRect, asset: String)] {
        guard isPortrait else { return [] }
        var targets: [(rect: CGRect, asset: String)] = []
        for pet in pets where !pet.isHidden {
            targets.append((rect: pet.frame, asset: pet.asset))
        }
        if let label = bubbleLabel, !label.isHidden,
           let owner = bubbleOwnerAsset {
            targets.append((rect: label.frame, asset: owner))
        }
        return targets
    }

    /// proxy 手势转发入口：单点 = 蹦回/小跳，双击 = 反应贴
    /// 纸（与旧 IslandPetView 手势同行为、入口换到 proxy）。
    func proxyTapped(asset: String, doubleTap: Bool) {
        guard let pet = pets.first(where: { $0.asset == asset }) else { return }
        if doubleTap { islandPetDoubleTapped(pet) } else { islandPetTapped(pet) }
    }

    /// proxy 启停同步：岛上无宠物时整体停用（isHidden + 关
    /// interaction），hitTest 链根本不进 proxy；有宠物才启用。
    private func syncProxyState() {
        guard let proxy = hitProxy else { return }
        let active = !pets.isEmpty
        proxy.isHidden = !active
        proxy.isUserInteractionEnabled = active
    }

    // MARK: APNG 统一驱动（(53) G③，核查结论见文件头）

    /// StickerView.tick(_:) 的运行时选择子：该方法是 @objc
    /// private，编译期不可见、运行期可达；本层只调它推进帧，
    /// 不碰 StickerView 任何状态（帧推进逻辑仍归它本体）。
    private let stickerTickSelector = NSSelectorFromString("tick:")

    private func updateStickerDrive() {
        let needed = !pets.isEmpty || reactionView != nil
        if needed, stickerDriveLink == nil {
            let link = CADisplayLink(target: self,
                                     selector: #selector(driveStickers(_:)))
            link.add(to: .main, forMode: .common)
            stickerDriveLink = link
        } else if !needed {
            stickerDriveLink?.invalidate()
            stickerDriveLink = nil
        }
    }

    @objc private func driveStickers(_ link: CADisplayLink) {
        for pet in pets {
            _ = pet.stickerView.perform(stickerTickSelector, with: link)
        }
        if let reactionView {
            _ = reactionView.perform(stickerTickSelector, with: link)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reseatAll(animated: false)
        updateVisibility()
    }

    private var isPortrait: Bool { bounds.width <= bounds.height }

    private func updateVisibility() {
        // 横屏保守隐藏（岛不在顶部）；竖屏恢复。
        let show = isPortrait
        for pet in pets { pet.isHidden = !show }
        if !show { hideBubble() }
    }

    // MARK: 落座 / 撤下

    /// 墙台分流送达：从出发点（主窗口坐标，与本层同屏几何）
    /// 蹦到岛上座位（弹簧 + 两下蹦跳）。爬升动画开始前先即
    /// 时置顶一次，不等守护拍（3.7 (41) 组1）。
    func receive(asset: String, fromRect: CGRect?) {
        refrontIfNeeded()
        seatPet(asset: asset, animated: true, fromRect: fromRect)
    }

    private func seatPet(asset: String, animated: Bool, fromRect: CGRect?) {
        guard !pets.contains(where: { $0.asset == asset }) else { return }
        // (53) M 固定双人组闸（岛层兜底）：选角数据源在登
        // 记表（setHome(.island) 已把非双人组改道回池，正常
        // 路径到不了这里）；万一有直达 receive 的非双人组，
        // 在此拒收并落面包屑，口径与登记表一致、不打架。
        guard PetHomeRegistry.islandFixedDuo.contains(asset) else {
            Breadcrumbs.log("island.seat rejected=\(asset) resident=fixedDuo")
            return
        }
        guard pets.count < PetHomeRegistry.islandCapacity else { return }
        let pet = IslandPetView(asset: asset, size: Self.petSize)
        pet.islandLayer = self
        addSubview(pet)
        pets.append(pet)
        reseatAll(animated: false)
        if animated, let fromRect {
            let target = pet.center
            pet.center = CGPoint(x: fromRect.midX, y: fromRect.midY)
            pet.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            pet.alpha = 0.6
            UIView.animateKeyframes(withDuration: 0.85, delay: 0, options: []) {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.35) {
                    pet.center = CGPoint(x: (fromRect.midX + target.x) / 2,
                                         y: min(fromRect.midY, target.y) - 60)
                    pet.alpha = 1
                }
                UIView.addKeyframe(withRelativeStartTime: 0.35, relativeDuration: 0.3) {
                    pet.center = CGPoint(x: target.x, y: target.y - 14)
                    pet.transform = .identity
                }
                UIView.addKeyframe(withRelativeStartTime: 0.65, relativeDuration: 0.35) {
                    pet.center = target
                }
            }
            showBubble(PetLines.islandHome.randomElement() ?? "", above: pet, duration: 2.4)
        }
        startTimerIfNeeded()
        updateStickerDrive()
        syncProxyState()
        if nextBubbleAt == 0 { nextBubbleAt = clockNow + 9 }
        if nextChatAt == 0 { nextChatAt = clockNow + 22 }
        logLayerState(reason: "seat")
        // (53) M：落座对账——resident=fixedDuo + 当前在座名单，
        // 真机一眼核「岛上恒为这对」。
        Breadcrumbs.log("island.resident asset=\(asset) resident=fixedDuo"
            + " seated=\(pets.map { $0.asset }.joined(separator: ","))")
    }

    /// 撤下（被召回/点按回台）：小跳一下淡出。回台的「到场」
    /// 由目标台自己的入场动画承接。
    func releasePet(asset: String) {
        guard let pet = pets.first(where: { $0.asset == asset }) else { return }
        pets.removeAll { $0 === pet }
        if chatLines.contains(where: { $0.pet === pet }) { endChat() }
        if bubbleLabel != nil { hideBubble() }
        UIView.animate(withDuration: 0.3, animations: {
            pet.transform = CGAffineTransform(translationX: 0, y: -10)
                .scaledBy(x: 0.8, y: 0.8)
            pet.alpha = 0
        }, completion: { _ in pet.removeFromSuperview() })
        reseatAll(animated: true)
        updateStickerDrive()
        syncProxyState()
        if pets.isEmpty {
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func reseatAll(animated: Bool) {
        guard isPortrait else { return }
        let cx = bounds.width / 2
        // 站位表（(53) M 改定）：居民恒为固定双人组、容量 2，
        // 站位只剩两档——双只 [−40,+40]（(43) 双只表原值，
        // 两只以岛中线对称分列＝双人居中口径）、单只 [0]
        // 居中（一只被召回/尚未到岛的过渡态）。(43) 三只表
        // [−54,0,+54] 随容量 3 一并退役（第三只不可能落座）。
        // 席位按双人组序分配（cat-live 左、dog-11 右），与
        // 到岛先后无关，站位恒定。
        let offsets: [CGFloat] = pets.count >= 2 ? [-40, 40] : [0]
        let ordered = pets.sorted {
            (PetHomeRegistry.islandFixedDuo.firstIndex(of: $0.asset) ?? .max)
                < (PetHomeRegistry.islandFixedDuo.firstIndex(of: $1.asset) ?? .max)
        }
        for (index, pet) in ordered.enumerated() {
            let offset: CGFloat = index < offsets.count ? offsets[index] : 0
            pet.seatFeet = CGPoint(x: cx + offset, y: Self.seatFeetY)
            let target = CGPoint(x: pet.seatFeet.x,
                                 y: pet.seatFeet.y - Self.petSize / 2)
            if animated {
                UIView.animate(withDuration: 0.5, delay: 0,
                               usingSpringWithDamping: 0.85,
                               initialSpringVelocity: 0.1, options: []) {
                    pet.center = target
                }
            } else if pet.center == .zero || !isAnimatingArrival(pet) {
                pet.center = target
            }
        }
    }

    private func isAnimatingArrival(_ pet: IslandPetView) -> Bool {
        pet.layer.animation(forKey: "position") != nil
    }

    // MARK: 点按回台 / 双击反应

    fileprivate func islandPetTapped(_ pet: IslandPetView) {
        if let target = PetHomeRegistry.shared.frontmostStage() {
            // 台侧入场动画承接「蹦回」；本层经登记回调撤下。
            target.receiveReturningPet(asset: pet.asset)
        } else {
            // 没有点播台在场：留在岛上，小跳 + 一句到家词。
            hop(pet)
            showBubble(PetLines.islandHome.randomElement() ?? "",
                       above: pet, duration: 1.8)
        }
    }

    fileprivate func islandPetDoubleTapped(_ pet: IslandPetView) {
        reactionView?.removeFromSuperview()
        let view = StickerView()
        view.crumbScene = "island-reaction"
        let asset = MiniBarPetStage.reactionPool.randomElement() ?? "dog-11"
        let size: CGFloat = 36
        var x = pet.frame.maxX + 2
        if x + size > bounds.width - 2 { x = pet.frame.minX - size - 2 }
        view.frame = CGRect(x: x, y: pet.frame.minY + 2, width: size, height: size)
        view.silhouetteHaloEnabled = (asset == "dog-11")
        view.setSticker(asset, mode: .loop)
        view.isUserInteractionEnabled = false
        addSubview(view)
        reactionView = view
        updateStickerDrive()
        view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.alpha = 0
        UIView.animate(withDuration: 0.32, delay: 0,
                       usingSpringWithDamping: 0.55, initialSpringVelocity: 1,
                       options: []) {
            view.transform = .identity
            view.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak view] in
            guard let view else { return }
            UIView.animate(withDuration: 0.3, animations: {
                view.alpha = 0
            }, completion: { _ in
                view.removeFromSuperview()
                if self?.reactionView === view { self?.reactionView = nil }
                self?.updateStickerDrive()
            })
        }
    }

    private func hop(_ pet: IslandPetView) {
        let base = pet.center
        UIView.animateKeyframes(withDuration: 0.45, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5) {
                pet.center = CGPoint(x: base.x, y: base.y - 9)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5) {
                pet.center = base
            }
        }
    }

    // MARK: 闲晃 / 冒泡 / 停聊（1s 心跳驱动）

    private var clockNow: TimeInterval { CACurrentMediaTime() }

    private func startTimerIfNeeded() {
        guard tickTimer == nil else { return }
        nextBubbleAt = clockNow + 9
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    private func tick() {
        guard isPortrait, !pets.isEmpty else { return }
        let now = clockNow
        // 气泡过期。
        if bubbleLabel != nil, now >= bubbleUntil, chatLineIndex < 0 {
            hideBubble()
        }
        // 停聊推进（居民 ≥2 只）：轮流冒泡，一句约 1.4s。
        if chatLineIndex >= 0 {
            if now >= chatLineUntil {
                chatLineIndex += 1
                presentChatLine()
            }
            return
        }
        // 闲晃：每拍随机一只小幅漂移（落座点 ±3pt）。
        if let pet = pets.randomElement(), Int.random(in: 0..<3) == 0 {
            let target = CGPoint(
                x: pet.seatFeet.x + .random(in: -3...3),
                y: pet.seatFeet.y - Self.petSize / 2 + .random(in: -1...1))
            UIView.animate(withDuration: 0.9, delay: 0,
                           usingSpringWithDamping: 0.7,
                           initialSpringVelocity: 0.4, options: []) {
                pet.center = target
            }
        }
        // 居民停聊触发（≥2 只）。
        if pets.count >= 2, now >= nextChatAt {
            startChat()
            return
        }
        // 单/双宠日常冒泡（到家库）。
        if now >= nextBubbleAt, let pet = pets.randomElement() {
            nextBubbleAt = now + .random(in: 16...30)
            showBubble(PetLines.islandHome.randomElement() ?? "",
                       above: pet, duration: 2.4)
        }
    }

    private func startChat() {
        guard pets.count >= 2 else { return }
        // 抽对：（3.7 (43) 路1）改随机抽 2 只（代固定 pets[0]/[1]）；
        // (53) M 后居民恒为固定双人组，抽对即这对，shuffled
        // 只决定谁先开口，机制不变。
        let pair = pets.shuffled()
        let a = pair[0], b = pair[1]
        let dialogue = PetChat.generate(a: a.personality, b: b.personality)
        chatLines = dialogue.lines.map {
            (pet: $0.speakerIsA ? a : b, text: $0.text)
        }
        chatLineIndex = 0
        Breadcrumbs.log("pet.chat surface=island"
            + " a=\(a.asset)(\(a.personality.label))"
            + " b=\(b.asset)(\(b.personality.label))"
            + " topic=\(dialogue.topic.label)"
            + " combo=o\(dialogue.openerIndex)/r\(dialogue.responseIndex)"
            + " lines=\(dialogue.lines.count)")
        presentChatLine()
    }

    private func presentChatLine() {
        guard chatLineIndex >= 0, chatLineIndex < chatLines.count else {
            endChat()
            return
        }
        let line = chatLines[chatLineIndex]
        chatLineUntil = clockNow + 1.4
        showBubble(line.text, above: line.pet, duration: 1.4)
        hop(line.pet)
    }

    private func endChat() {
        chatLines = []
        chatLineIndex = -1
        hideBubble()
        nextChatAt = clockNow + .random(in: 25...45)
    }

    // MARK: 气泡（挂在宠物下方：头顶上方是屏幕沿与岛框，
    // 气泡垂在岛下沿之下，像挂在岛上说话）

    private func showBubble(_ text: String, above pet: IslandPetView,
                            duration: TimeInterval) {
        hideBubble()
        guard !text.isEmpty else { return }
        let label = UILabel()
        label.font = .systemFont(ofSize: 11)
        label.textColor = .darkText
        label.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.numberOfLines = 2
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.text = "  \(text)  "
        label.sizeToFit()
        let w = min(label.bounds.width + 12, 190)
        let h: CGFloat = 26
        let x = min(max(4, pet.frame.midX - w / 2), bounds.width - w - 4)
        label.frame = CGRect(x: x, y: pet.frame.maxY + 4, width: w, height: h)
        addSubview(label)
        bubbleLabel = label
        bubbleOwnerAsset = pet.asset
        bubbleUntil = clockNow + duration
        label.alpha = 0
        label.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.65, initialSpringVelocity: 0.7,
                       options: []) {
            label.alpha = 1
            label.transform = .identity
        }
    }

    private func hideBubble() {
        bubbleLabel?.removeFromSuperview()
        bubbleLabel = nil
        bubbleOwnerAsset = nil
    }
}

