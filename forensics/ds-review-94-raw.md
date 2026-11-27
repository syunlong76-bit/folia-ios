=== reasoning ===
我们需要回答中文。任务：对抗评审，逐条挑错，给四问根因排序、最小修法、自证面包屑。必须直接、挑错。需要深入分析日志判读和代码审计。不能客套。需要遵守约束。要指出证据不足、机制可能错、修法翻车。最后四问。

我们需要组织。首先逐条异议：判读1-8，审计 B1等。需要识别逻辑漏洞。

关键信息：iOS原生音乐App照片墙+歌词舞台+全局特效。93失败。日志 upload 1201行 主会话约2分钟开头滚掉，上一会话尾巴。p93面包屑只有4条。deck size=112/43, host=stage, pop gap=762, dismiss r=dim. mem/fw dt/xmas fps/deck glyph cov fb/tap own 0条。控制台 present 02:36:40.262 -> pop gap=762ms; wall.scroll max=633.2ms; 92 606.4ms. 93 moved polaroid print out popup path and split frames, gap up. 结论卡点控制台 viewDidLoad 构建 + first layout; pop gap includes crossDissolve ~0.3s then ~400ms main block.

需要挑错：pop gap 762 到 present 时间？日志时间？ "present 02:36:40.262 → p93 pop gap=762ms" 这个 pop gap 是 present 到 dismiss? 需明确。 pop gap 可能从 tap/present 到 pop? If includes crossDissolve 0.3s, 762-300=462, not 400. 92 606.4, 93 higher only 156ms, but variation? 只有单样本，不能断定不降反升；wall.scroll max 633 同期独立可能锁主线程。需要相关时间戳同窗口、main thread hitch, viewDidLoad time, layout, image decode, cache hit; p93 无 mem/fw dt 等。缺少面包屑不能归因 viewDidLoad。移出打印后 gap不降反升可能因为新增分帧调度/首帧空/图片首次解码/字体/符号/UIVisualEffectView blur首次。需要拆分 present start, VC init, viewDidLoad start/end, layout subviews, draw, first frame commit, transition completion, pop. 仪器含转场时长需校准 pop gap定义：若 pop gap from present begin to completion，包含 transition；若 includes crossDissolve 0.3 but target <50ms 不合理？目标 <50ms maybe pop gap is tap-to-pop? Need define. 762 vs target <50 cannot include 0.3. 需要自证。

判读3：1次实例 2ms A1生效，但单实例不能证明所有 outside 路径；hitTest 直达+统一 dismiss。可能背景点外关闭在子视图/overlay/parent? 2ms 仅证明本次。不能外推。

判读4：3次旋转 freeze->landed ~330ms, 主会话无 >1.2s日志间隔，用户报卡顿。330ms freeze 帧机制是 app 人为 freeze 动画？ 若 freeze 帧显示静态快照到 landed，330ms 对系统旋转正常? 用户感受卡顿可能由于 WebView 画布 resize 黑/重排、布局集切换导致帧率低、字体左切、场景 top 45%。图五 style=sonnet WebView：场景压顶部45%带、下方黑、歌词左切、点阵粗糙 -> 可能是 WebView viewport/容器 aspect fit/横屏布局未全屏，canvas CSS尺寸/DPR错误，或原生舞台容器只给顶部? 不能只凭日志无线程阻塞就说不是卡顿；330ms landed 是 freeze overlay 结束，真正的 WebView 内容 resize 可能在 landed 后异步发生，未计入。需要用 breadcrumb: rotation start/orientation, freeze show/hide, landing layout, webview frame, canvas resize, contentSize, fps/hitch, first stable frame, glyph overlays. 分环：原生窗口/容器 frame、WebView frame/resize、JS/CSS layout、canvas backing store、stage layout set、release freeze.

判读5：黑屏：wall.scroll identityChanged=1 lattice=15/20/21 rebase/reload hitch 30.8 p95 152.9; wall.render.audit visible=0 origin.x -930576 to -1189051 ~ -89k/s drift=4783 limit 2280; hit84 pkv=410933. 结论墙虚拟原点失控飞出（fling/惯性未收敛或 identity 变更后未重锚），视口百万点外空区。需要挑错：origin.x 百万点可能不是错误，可能是 virtual origin/world coordinate 设计，visible=0 更关键。drift=4783 上限2280，pkv 410933 单位? pkv 可能 pan velocity? origin变化速度 -89k/s 是 audit 行间差/时间? 日志行间隔? 主会话? 上一会话尾巴。 identityChanged=1 与 lattice/rebase/reload 同数说明模式切换，但顺序、时间差未知。 visible=0 连续可能是布局在隐藏/过渡期间；黑屏可能仅是交叉淡化覆盖/替代表空白/快照未生成；origin.x 负值可能由 transform/anchorPoint 坐标换算，不是空区。可见 visible=0 却 origin 变化，说明仍在跑惯性/渲染审计，隐藏期墙仍跑惯性高度可疑。 需要区分：fling 未停 vs identity 重锚缺失 vs 隐藏期更新。 证据：pkv 高、drift 超限、visible=0、identityChanged=1 同时。 根因排序可能需要 identity change during fling causing unanchored virtual origin; but visible=0 maybe audit only reports visible rows, origin can be arbitrary if no rows? Need minimal fix: on identity change/mode switch, hard stop display link/fling, cancel animations, invalidate layout, reset contentOffset to anchor for current item, clamp origin to valid content bounds, freeze render until layout stable, crossfade only after first nonempty visible snapshot. Breadcrumb: switch begin mode from/to, identityGen, before/after contentOffset/origin, flingActive/pkv, audit visible count/valid range, rebase reason, first stable visible=1, black overlay show/hide, frame count. Need self evid.

判读6：内存 285→359, no fx. 结论 window未越450, fx未确认. 正确但注意 footprint 与 peak 不同；控制台打开+28; 未越450 only sampled, 峰值可能缺失因环形缓冲开头滚掉； p93 wallcache 未出现初始时机滚出; 不能确认墙缓存 120-180. Decode concurrency? Need add memory breadcrumbs periodic on scene/fx/rotation/control open and peak high-water. 特效未开不能证明特效安全。

判读7：特效页投诉不在日志，未确认。正确，但不应作为排除；需要复现。

判读8：风删除代码层，未开未确认。正确；代码删除不等于 runtime 无其他 stopWind路径/自动关闭定时器/手势取消。

审计B1：台高 112 ✓ size=112/43. 但 miniPlayButton空圆：结论丢失环在工厂之后（视图栈/setImage覆盖），cov自证只测工厂出口，仪器装错层。 挑错：图三“主页墙展开台”是否使用 MiniBarQuickRowView？ home wall miniPlayButton maybe different path from console. size=112/43 是 deck size? host=stage? 需要确认图三控件实际类/实例标识。 DeckGlyph82.coreGlyph same factory? 控制台 pause/prev/next 可见，未证明 play/pause 参数相同。 “pause字形无兜底，而图三播放态期望 pause” 支持可能不是视图栈而是 glyph 工厂 pause 分支空/fb缺失。 图三中央播放钮空圆，若期望 pause，且 pause 无兜底，工厂 pause 可能返回 nil/透明；但控制台 pause 可见（图四 pause 真机可见）则工厂 pause branch 能产出。 除非图四 pause 是控制台同工厂但不同 scale/tint/状态。 需要添加按钮最终渲染层 probe：setImage 后 image size/tint/nil, layer.contents, subviews z, effect view frame/alpha, final snapshot pixel count/差异化. 不要只测工厂出口。 修法：在 miniPlayButton 上增加 render audit after layout: current image asset id, image ptr, template/tint, subview count/z, alpha, mask, effect view, final screenshot hash; 在 setImage 后用 async next runloop assert layer contents; 避免 insertSubview at 0 覆盖? At 0 below image? UIVisualEffectView at 0 behind, gradient at 0 maybe behind. setImage覆盖 by refresh? Need use state-driven update once, remove duplicate glyphs, ensure pause fallback. Minimal fix maybe cache final glyph and reapply in layoutSubviews; add fallback for pause. But root likely setImage被刷新覆盖 or button state not updating. Need mention cov/fb should be at final layer not factory. Also "cov自证只测工厂出口" correct but conclusion "丢失环在工厂之后" evidence insufficient because pause no fallback and图三播放态; if factory pause returns empty due to config (e.g., lineWidth/scale/tint) could show empty. Need rank: 1 state/glyph selection (pause branch or current state not updated) 2 final view stack/refresh overwrite 3 tint/effect/blur masking. Instrument at final.

C1/C2图证到达但不一定全状态/暗色/横屏。C3胶囊两页式样不同: 与样片同一组件不符；交叉淡化只覆盖替代表/架视图，未碰照片墙模式0. Need ensure two pages same母版. C3 crossfade could hide black by overlay? But black maybe origin.

C4控制台宽：源码 cardW min(620,屏宽−20) but真机 292-300. 结论机制未定。 需要挑错：图四以音量行反推卡宽 ≈292-300, 但音量行宽可能不是卡宽-24（padding不同、内嵌容器、固定宽），面板包围盒≈299 maybe measure from screenshot with scale uncertain; 不能证明620公式未执行。 可能屏宽 320? iPhone? 屏宽−20=?? 若 296? 竖屏 iPhone SE width 320 -> min(620,300)=300. 对！如果设备屏宽 320，公式结果 300，不是370。 用户图四 maybe iPhone SE? Need check. 之前(92) 296; if screen width 390 -> 370. 实测 299 suggests device width ~320 or bounds not full. Also viewDidLayoutSubviews bounds could be card itself not screen? If self.view bounds? Need log UIScreen bounds, window bounds, view bounds, safeArea, cardW result, active constraints. Height formula 658 vs屏高−180. 658pt = 77% if screen height 855? 77% of 855=658. User wants 54.9%: 469. Need not just revert numeric; "原来"可能82. 需以样片唯一规格。 Need verify sample spec. 修法: compute from window width not presenting container; log calc inputs/output; apply after safe area; if sample says 370? Wait样片? 控制台宽 likely sample. 最小: use window.bounds.width - 20 in layout, set explicit width constraint on content container, not relying on self.view.bounds if context is form sheet/page sheet. Also if need 370 on 390. But if device small, min. Need breadcrumb.

A1: one instance. A2 code only. A3 fail. A4 memory caching. A5 no sample.

D: 圣诞 scale=1 4处 UIGraphicsImageRenderer fmt.scale=1; screen scale=3 -> 1x raster. 对模糊实锤? 图五 sonnet WebView不是圣诞，所以圣诞糊未真机确认? 代码实锤是1x栅格化，但最终视觉是否糊取决于精灵在屏幕的绘制尺寸与图像点尺寸、是否再缩放。 若精灵按 points*? 1x image displayed at natural points on 3x screen -> upsample. Need confirm draw sizes. 修法 scale=min(screen scale,2) maybe. But memory. 3000+3000? 7100 one pot. Need budget. Also 3000+3000 particles at scale=3 huge memory: each sprite maybe 64x64? Need compute. Could use vector CAShapeLayer/CAEmitter? But constraint. Minimal: use fmt.scale=min(UIScreen.main.scale,2) for static sprites, share atlas, cap particles, LOD. For WebView sonnet: canvas width=CSS width*dpr capped2, backing store, contentsScale, resize reset. Stage texture cap 200-250MB. Need discuss scale 2 vs3 cost. If canvas 390x844 CSS at dpr2 = 780x1688 ~5.3MP RGBA 21MB per buffer; dpr3=1170x2532 11.85MP 47MB. Multiple buffers/canvas/WebGL textures. Native sprites: atlas 2048x2048 @2x = 16? Wait RGBA: 2048*2048*4=16MB at 1x pixels; scale2 atlas maybe 4096x4096 67MB if same point size. At 3x 9x memory. Need choose 2x, shared atlas, not per-sprite renderer. For lyrics stage texture 200-250. dpr2 likely enough; scale3 only for text/vector maybe. Use dynamic: cap total bytes, render sprites at 2x, upscale? Need.

E烟花未确认.

缝头像缺失: 用户投诉，代码没有，port88 seam=avatarless，样片从未移植，两轮漏。 对。 还有歌单缝竖排标题溢出叠印，图二实锤；主页缝和歌单缝两套独立，用户要求全页缝以主页缝唯一母版共用同一实现。 Need修法：先移植头像/二维码到统一 seam component, unify playlist seam to home seam, avoid竖排标题固定帧高，lineBreak/truncate/字号/滚动? Minimal: use common母版组件; remove竖排书脊式; title container measured; QR login from avatar; breadcrumb: seam kind/class, avatar present, qr present, title lines/frame overflow count, component id, x. But this is not Q? We should include.

Need answer format: 先总判：证据链不足。逐条异议。每问根因排序、最小修法、面包屑。 Need be concrete.

Let's parse likely log details. p93 breadcrumb only 4; mem/fw dt/xmas fps/deck glyph cov fb/tap own all 0. If instrumentation code落码 but no logs, possible log level/feature gated? Need inspect: p93 namespace maybe only emits when debug? But other p93 logs present. Could be sampler not called due early return, or ring buffer lost? Main session 2min 1201 lines, not all lost. Need distinguish "未触发" vs "未命中样本". mem should trigger on console open? p93 mem not appear despite console opened, so instrumentation bug, not no sample. fw dt? xmas fps no fx. deck glyph cov/fb should appear on deck build (host stage) maybe absent => instrumentation not executed or wrong layer. tap own for outside tap? absent though dismiss r=dim appears; tap own归属 code maybe in wrong path. So A5 probe is broken for these. Need fix instrumentation first: ensure p93 mem on scene active/console present, glyph audit at final view, tap own in hitTest before dismiss. Otherwise next log can't cut.

"主会话开头已被环形缓冲滚掉" but main 2 min only? Ring buffer maybe fixed lines and high volume. The main session 02:34:54–02:36:49; upload 1201 lines; if ring buffer rolled, older events missing. But p93 mem initialization scrolled; however console open at 02:36:40 should be near end, not scrolled. Gap and dismiss near end. mem maybe not emitted on open. Need.

Need identify timeline: p93 pop gap=762 at console present 02:36:40.262. dismiss at? 02:36? wall.scroll max 633.2 same period. If max scroll hitch 633.2 might occur at control open due wheel? But pop gap. Need correlate exact timestamps. 92 606.4 is another run/device? Not controlled. Single run. Need A/B not valid due sample variability.

"pop gap 仪器含 crossDissolve 转场时长（约0.3s），即便扣除仍有约400ms主线程阻塞" Actually 762-300=462. More importantly，crossDissolve duration maybe UIView transition 0.35/0.4; not measured. If target <50ms, then gap likely from tap to presentation; including transition impossible. Need define. 需要把 present 的 "开始/结束" 和 "首帧提交" 分开. 最小修法: 分帧构建控制台：先以骨架/占位呈现，viewDidLoad 只建容器，重内容 async staged (header, strip, queue, polaroid) after transition; 预取/预 layout 控制台单例在后台? But UIKit main. Use placeholder snapshot; lazy sections; avoid cover first frame. But user style sample. Need not alter spec; load skeleton with exact layout. Freeze transition? Hmm.

Need "挑错" includes "我方结论：卡点不在打印，在控制台 viewDidLoad构建+首次布局" evidence insufficient because 93 moved print out and gap up not enough; possible新增分帧调度导致首帧延后 or crossDissolve transition itself, or image decoding on first layout. Need log section-level time. 最小修法: instrument viewDidLoad start/end, each section build, layoutSubviews total, first draw, image loads; if section >50ms move off first frame or prebuild after placeholder. Use signpost. Breadcrumb: console.present tap, vc.init, vd.start, vd.end(ms), layout(ms), firstCommit(ms), transitionEnd, popGap, mainHitch. Also memory.

判读1: p93 只有4条，but that itself indicates instrumentation not wired at final layers; deck size=112/43 and host=stage. Need note "mem/fw dt/xmas fps/deck glyph cov/fb/tap own 全部0条" cannot interpret absence uniformly because different gating; should tag each expected trigger and count. For deck glyph cov/fb: if console opened, should have glyph audit at build? It didn't; so cov/fb not on final view. Therefore B1 conclusion "工厂本身没坏" strengthened? Wait if cov/fb absent, maybe no audit; control glyph visible from screenshot. Screenshot evidence? "图四 pause/prev/next真机可见" okay image. But no log. Need not over rely.

判读4: 图五 style=sonnet WebView. The scene top 45%, below black, lyric left clipped, dot matrix coarse. Need likely WebView `UIView` frame/scrollView inset? For横屏舞台: WebView容器使用竖屏尺寸或 aspect fit; CSS `100vh` not updated after rotation; `meta viewport` width=device-width but orientation change; safe area. Or layout set only top safe area? Need分环:
A native stage container frame (full screen? top band)
B WebView frame and scrollView contentInset/adjustContentInset
C HTML/CSS layout viewport (innerWidth/Height, devicePixelRatio, orientation media query)
D Canvas/WebGL backing store ceil(CSS*dpr) and CSS scale; coarse due dpr reset to1 on resize.
E Freeze snapshot release before content stable -> shows old portrait canvas stretched/cropped? If freeze overlay released at 330ms but WebView still resizing, shows top band? Actually freeze frame maybe shows snapshot of previous? User sees black below.

Need self evidence: on rotation: log UIScreen bounds, window bounds, stage container frame, webview frame, scrollView.contentInset, safeArea, JS `window.innerWidth/Height, devicePixelRatio, canvas.width/height, canvas.style.width/height, drawableScale, orientation` before/after resize; freeze show at t0, native layout t1, webview resize t2, JS layout done t3, firstRender t4, freeze hide t5, stable frame t6. FPS/hitch.

Minimal fix: do not release freeze at fixed 330ms; release after webview first commit stable or after 2 frames; on rotation set webview frame full stage and disable auto content inset; send explicit resize with new bounds and dpr capped2; reset canvas backing store and redraw; CSS use `100dvh`? Need safe area. For sonnet, set viewport meta viewport-fit=cover? Use safe area env. But样板. Minimal: synchronize stage layout set and webview frame before freeze release; force layout; wait `didFinishNavigation`? For rotation use native overlay with simultaneous animation; after layout call JS resize with width/height; wait for ready message. Ensure CSS no fixed aspect. Log.

Q1 root: Need rank: 1 identity change while fling/inertia active and no anchor reset -> virtual origin continues; 2 hidden/alternate view mode still display link running and auditing origin, causing unbounded pan; 3 audit `visible=0` caused by transition overlay or content not prepared, not necessarily origin. Need decide. Evidence: identityChanged=1, rebase/reload same; origin speed 89k/s, pkv 410933, drift huge. If fling velocity 410933 (points/s?) then in ~2.7s moves 1.1M; origin delta ~258k over? Actually -930576 to -1189051 delta -258475. At -89k/s ~2.9s. So high velocity could explain. identityChanged likely triggers content size reset but contentOffset retained. If identity changes and contentSize becomes small, offset can be out of range; UIScrollView may not clamp during deceleration? Need. Also virtual origin may be artificial coordinate independent of scroll. Minimal: on mode/identity transition, stop scrolling/deceleration (`setContentOffset(current, animated:false)`, `layer.removeAnimation`, cancel display link), disable bounce, reset virtual origin to current visible item anchor, clamp to valid range, suspend audit until visible. Add state machine: idle/fling/dragging/modeSwitching. In render audit, log min/max valid origin, clamped flag, visible indices, flingActive. Breadcrumb: `wall.modeSwitch begin gen identity from/to offsetBefore originBefore fling vel`, `wall.reanchor anchorIndex originAfter validRange`, `wall.fling stop reason`, `wall.render.audit visible count firstIndex lastIndex`. Need ensure no black: keep previous snapshot until first visible=1 then crossfade. But "C3只做交叉淡化没碰原点" yes.

Q2 root ranking: 1 WebView canvas/layout resize after freeze release (not native layout) causes visible glitch; 2 freeze release too early/fixed timer; 3 stage layout set switching not accounting landscape/safe area, causing top band/left clip; 4 actual main thread blocking? Logs no >1.2s but microhitches can be <1.2 and cause user feel. 330ms freeze->landed may be okay but content resizes after landed, not counted. Minimal: hold freeze until `rotationLayoutStable` message after WebView resize/canvas redraw; native container full screen; disable contentInsetAdjustment; update CSS orientation/height; set canvas backing store dpr capped2 and redraw; release after 2 stable frames. Breadcrumb as above. Need "不要只减 freeze 时长" because shorter freeze reveals black sooner. Good.

Q3: yellow face. Need identify likely. Fx independent window level 1500 root interaction off pure display; main window full FxOverlayHost91 with 祝福卡/写灯钮/推荐卡; hitTest重写:遍历子视图、帧含点且 super.hitTest 非自身才交回. Yellow face possibilities: 孔明灯祝福卡深棕+琥珀边 (yellow/brown layer) high; 写愿望页 (likely yellow?);烟花闪光 alpha残留 white not yellow;开灯暖光层 yellow/amber. Since "点出黄色面、什么都点不动": likely a full-screen warm light overlay in Fx window (interaction disabled) or FxOverlayHost with an overlay subview intercepting. But Fx window root interaction off means its subviews cannot receive? Actually if window is non-interactive (isUserInteractionEnabled=false) hitTest returns nil? If window level above main, a window with userInteraction disabled should allow touches to windows below? Need iOS hit-testing across windows: UIWindow hitTest; if window's isUserInteractionEnabled false, hitTest returns nil? The window may still be considered? UIApplication sends touches to window whose hitTest returns view. If top window returns nil, lower windows? I think window hitTest returns nil if user interaction disabled? Yes likely. But if FxOverlayHost on main covers full screen and hitTest logic returns overlay host itself for points not in whitelisted subviews, then it swallows. `super.hitTest` non-self check? Need parse: In FxOverlayHost hitTest,遍历子视图、帧含点且 super.hitTest 非自身才交回. This logic maybe: if subview hit and super.hitTest point returns not self, return subview; else return self? That means host itself becomes hit view when no interactive child; if host is userInteractionEnabled, it swallows touches. But if it's a full-screen overlay with clear background, it eats all. Need minimal fix: set overlay host `isUserInteractionEnabled=false` by default; only enable for active interactive cards; override hitTest to return nil unless point inside interactive whitelist and that child hit; never return self. Also Fx window disable interactions entirely; ensure animated yellow layer has `.isUserInteractionEnabled=false`. Need clear yellow layers on completion; alpha to 0 and removeFromSuperview; reset blend/additive layers.

Need list "黄色面可能" rank:
1 开灯暖光层/灯光 fx 全屏 amber overlay 挂在 Fx window or overlay host, alpha未清, interaction off.
2 孔明灯祝福卡/写愿望页的深棕渐变琥珀边大卡片，若 frame 被布局成全屏或 transform scale 异常，可能看似黄色面; its overlay host swallowing.
3 写愿望页 modal with yellow background/snapshot in Fx overlay host.
4 烟花闪光 layer white alpha residual plus warm background? Less likely.

Also hitTest paths:
- FxOverlayHost 自身成为 hitTest 返回（return self）吞掉所有点击。
- 子视图 `isUserInteractionEnabled=false` 但父 host 仍接收；命中透明/全屏容器。
- 子视图 frame 用 superview 坐标/transform 未转换，误判命中；或者子视图 alpha=0/hidden=false 仍参与 hitTest.
- overlay host 在窗口消失后未移除，透明但仍拦截。
- 主窗口 root 的 hitTest/dismiss console 统一处理，可能把点按路由到 dim/close。
- Fx window level 1500 虽 root关交互，但某些子窗口/子视图重新开启了 userInteraction (e.g., UIButton in Fx window) because window root off? If subview enables? If super disabled, no. But if window `isUserInteractionEnabled=true` and subviews false but root returns? Need.
- 全屏 `UIView` with `backgroundColor=.clear` but default userInteraction true. Need set false.
- 使用 `super.hitTest` 非自身才交回：如果 child 在点内但 super.hitTest 返回 host（because child is non-interactive), condition fails -> host swallows. Also if point outside child but inside host, what return? Need log.

Minimal fix: overlay host hitTest returns child only if child is interactive and contains point; otherwise nil. Do not return self. Use `point(inside:with:)` false if no enabled interactive descendants; or override `point(inside:)` returns false. Add `accessibilityIdentifier`/debug name to yellow layers; log hitTest chain names, reason, returned view class, overlay visible/alpha, fx window level, interactive whitelist. Breadcrumb: `fx.hitTest point class chain decision returned`, `fx.overlay state id/frame/alpha/userInteraction`, `fx.layer show/hide id`, `touch begin view`. Self evidence: tap yellow face logs `fx.hitTest guest=... hostDecision=passthrough/ swallow returned=...`, `fx.overlayCount`, plus after fix returned main content button.

Q4: Lyrics blur. Native Christmas scale=1实锤. WebView sonnet should check:
- viewport meta `width=device-width, initial-scale=1, viewport-fit=cover`; devicePixelRatio; `window.devicePixelRatio` maybe 1 in WKWebView if `pageZoom`/`scrollView.zoomScale` not 1? WKWebView contentScaleFactor? 
- canvas.width/height must be CSS size * min(devicePixelRatio, maxDpr) not fixed; after resize reset width/height clears context and resets transform; if not reset, canvas stretched coarse.
- canvas CSS width/height and backing store mismatch; `image-rendering`; CSS transform scale; WebGL drawingBufferWidth/Height; `preserveDrawingBuffer`; `ctx.scale(dpr,dpr)` and redraw.
- WKWebView `contentsScale` inherited screen; `scrollView.zoomScale`; `meta viewport` user-scalable; `pageZoom`; `UIWebView`? 
- stage WebView opaque/background; using snapshot size lower res; `UIGraphicsImageRenderer` for snapshot? 
- For text particles using sprite texture generated at low res; Three.js setPixelRatio min(dpr,2) sample; native uses CoreGraphics. For WebView style, if canvas backing store capped too low or dpr=1 due hidden/offscreen, blur.
- Memory constraint: texture budget 200-250. Scale2 vs3: pixels 4x vs9x relative 1x; vs scale2, scale3 is 2.25x texture memory. For 2D canvas full screen: at 390x844 CSS, dpr2 ~5.27MP*4=21MB per buffer; dpr3 ~11.86MP*4=47.5MB. Multiple canvases (particles, trail, lyrics, WebGL double buffer) scale. At dpr3 with 5 buffers ~237MB just stage, risk. At dpr2 ~105MB. Sprites/atlas: 2048² RGBA=16MB; 4096²=64MB; 3x may force 4096 atlas where 2x fits 2048, 4x memory. Use dynamic DPR cap2 for full-screen canvas; scale3 only small text/UI? Lyrics particles can use vector text rendered at 2x to texture; use MSAA? Minimal: cap dpr at 2, allocate backing stores from actual bounds*scale, redraw after rotation/resize, clear and reset transform, `canvas.width = round(cssW*dpr); canvas.height=...; ctx.setTransform(dpr,0,0,dpr,0,0)`, share one atlas, cap particle count, reduce offscreen buffers, use `UIGraphicsImageRendererFormat.scale = min(screenScale,2)` for native sprites; for text render at 2x and use mipmaps? Actually mipmaps can blur; use linear filtering. Need self breadcrumb: `stage.scale style=sonnet cssW/H dpr canvasW/H ctxScale zoomScale contentsScale`, `stage.resize from/to`, `stage.firstFrame ms`, `stage.fps`, `stage.textureBytes`, `stage.particleCount`, `stage.snapshotScale`. For native Christmas: `xmas.sprite id scale fmtScale pxSize drawSize atlasBytes`. Need log at renderer creation and rotation.

Need address all audit items maybe not just q. The final answer should be direct.

Let's design structure:

0. 总判：判读把“无日志”当“无发生”、单样本当A/B、未定义pop gap、跨窗口/转场/异步未分环。先修探针，再谈根因。列出“一刀切”面包屑原则：唯一事务id、阶段时间、最终渲染层、hitTest返回、有效范围。

Then I. 逐条异议:
1 p93 breadcrumb: absence not same; mem should trigger on console open and didn't => instrumentation故障; deck glyph cov/fb absent => not at final button; tap own absent though dismiss occurred => tap own instrument wrong path. 结论：A5不可作证；B1需最终层探针。
2 pop gap: 762 vs 92 606 single sample; includes transition; target <50 unaligned; 93 move print not enough. Need split phases. 不能断言卡点在viewDidLoad; 首帧图片解码/新增分帧/转场/crossDissolve/毛玻璃首用/字体/约束. Minimal fix staged skeleton; breadcrumb.
3 dismiss: one instance only; 2ms proves only that path; not all outside (child/overlay/window). Need enforce hitTest return nil for overlay, log.
4 rotation: no >1.2s doesn't rule out 330ms freeze or post-landed WebView resize; 图五 points to layout/viewport/resize, not just native block. freeze 330ms may be expected; need measure first stable frame after landed. 
5 black: origin negative not necessarily empty; visible=0 and hidden audit; identityChanged/fling correlation not proven; need order and units. Possible transition overlay. Need reanchor/stop.
6 memory: sampled footprint not peak; fx unconfirmed; wallcache init rolled; cannot claim ≤450 for all. Need high-water periodic.
7 fx complaint outside log: cannot confirm or refute; must not close.
8 wind: code deletion not runtime; other stop paths. Need runtime breadcrumb.
Audit items:
B1 evidence insufficient; pause no fallback makes factory suspect; test final layer. 
B2/C1/C2 screenshot only static/one orientation; okay for arrival but need state/dark/landscape.
C3 two pages different violates sample; crossfade not fix black.
C4 measurement assumptions; cardW 620 may not run because bounds not window or device width 320; need log calc. Height 658 vs 54.9 conflict; don't guess "原来", check sample spec. Rollback values not enough if sample says other.
A1 single; A2 code only; A3 fail; A4 not confirmed; A5 broken.
D scale=1 code evidence but final blur depends draw size; sonnet not xmas. 7100 one pot count not itself root; need budget/LOD. 
E no sample.
Seam: missing avatar true; two implementations conflict; title overflow due fixed frame. Need unified母版.

Then Q1-4.

Need perhaps mention "不要用 93 的 C3 crossfade 覆盖黑屏 because source wall still invalid; crossfade from black to black". For minimal fix: mode switch state machine.

Let's build each Q with "异议/根因排序/最小修法/面包屑".

Q1:
异议: "原点失控飞出"证据链不闭合：origin 百万点可能虚拟坐标；visible=0 can be隐藏期; drift 超限 indicates audit not clamped but not necessarily visual black; identityChanged=1 and fling high pkv correlation but no order. 
根因排序:
1. identity/mode切换时未停止 deceleration/inertia，contentSize/rebase 后 offset/虚拟原点未重锚，惯性继续在旧坐标系跑（最符合 pkv高+identityChanged+origin速度）。
2. 隐藏/替代表期间 display link/渲染循环未暂停，旧状态继续推进；交叉淡化只遮 UI，不修 state。
3. 布局/坐标换算单位错误/transform导致origin负百万，或 audit 只在无可见项时记录，实际视口未空。 
Minimal:
- 进入 modeSwitch: 增加 `wall.state=modeSwitching`; cancel display link timer, stop decel; `scrollView.setContentOffset(current,false)`? If virtual origin, reset anchor to current item index; clamp origin to valid content; set contentSize after layout; disable bounce.
- After reload/rebase completion, restore anchor; only then crossfade; keep previous snapshot until `visible>0` and first layout stable.
- Add clamp in render update: if fling active and identityGen changed -> ignore old velocity; clamp.
- Logs: switch id/gen mode from/to; pre/post offset/origin, validMin/Max, pkv, fling; `wall.reanchor reason anchorIndex`; `audit visible first/last clamped`. Need one line per phase. 
Self proof: Next log should show on switch `flingActive=false before rebase`, `origin within [min,max]`, `visible>0 before crossfade`, no `drift>limit`; if black still, audit line `overlay/visible=0` pinpoints.

Q2:
异议: 330ms not necessarily卡; no >1.2s doesn't measure dropped frames and post-landed. 图五 is sonnet WebView, likely viewport/canvas not full/resize. 
根因排序:
1. WebView canvas backing store/ CSS viewport resize after rotation not synchronous; freeze released before content redraw -> stale/cropped top band, coarse.
2. Stage layout set/container frame uses portrait/safe area or top band; `contentInsetAdjustmentBehavior`, `scrollView` insets, aspect-fit.
3. freeze release fixed timer/landed too early (or too long) not tied to first stable frame; native layout block.
4. 真正主线程阻塞 minor compared.
Minimal:
- On rotation: keep freeze; perform native layout to full window (safe area but stage fills), set webview frame; set `scrollView.contentInsetAdjustmentBehavior=.never`; call JS with new size; canvas resize sets backing store = CSS*min(dpr,2), reset transform, redraw; wait for `stage.ready`/two frames; then release freeze.
- For sonnet CSS: `html,body,#stage{width:100%;height:100%;overflow:hidden}`; use `100dvh`? Need maybe. Avoid fixed aspect. 
- Logs: rotation id, phase timestamps: freezeStart, nativeLayout, wkFrame, JSResize, canvasW/H/dpr, ready, freezeEnd, stableFrames. 
Self proof: next log shows canvasW/H match frame*dpr and ready before freeze hide; visual no top band.

Q3:
异议: 黄色面 unidentified; cannot assume fx window. Need log hit chain. Fx window interaction off should pass, so if still swallowed likely FxOverlayHost91 returns self or a stale full-screen overlay. Yellow could be warm light/祝福卡/写愿望. 
根因排序:
1. FxOverlayHost91 hitTest 返回自身/全屏透明容器吞点（最大）。 `super.hitTest` 非自身条件会把非交互子视图所在点落回 host。
2. 全屏暖光/闪光/祝福层未移除或 alpha>0 且 userInteractionEnabled 默认 true；挂在主窗 overlay 而非 Fx 窗。
3. 孔明灯祝福卡/写愿望大卡片 frame/transform 错误铺满屏幕，或 dim 遮罩没关交互。
4. Fx 独立窗 root关交互但子视图/窗口重新开启？ less if root off.
Minimal:
- OverlayHost hitTest: only return interactive whitelisted child if `point(inside)` and child enabled; otherwise return nil, never self. Set host `isUserInteractionEnabled=false` default; enable temporary? Actually if host false then children cannot receive. Better override `point(inside:)` to false unless a whitelist contains point; hitTest iterate only interactive whitelist and return child; otherwise nil. Do not use super.hitTest self fallback. All decorative layers `isUserInteractionEnabled=false`; on hide remove layer and zero alpha, cancel animations.
- Fx window interaction off, level 1500, but ensure `window.isUserInteractionEnabled=false` and no subview toggles. If need buttons, they should be in main overlay host whitelist not Fx window.
- Add hitTest breadcrumb before fix with chain, returned class, host decision. 
Self proof: tap yellow returns main content; log `fx.hitTest returned=nil` or `returned=WriteButton`; `fx.overlay hidden id`. If still swallow, chain shows returned host.

Need mention "黄色面" if it is warm light fx: `fx.warmLight` show/hide id; clear on `fx.stopAll`. If write wish page: if modal is in Fx window with root off, buttons won't work; if in overlay host returns host. Need move interactive page to main window/normal modal, not Fx pure display. That's minimal? "点出黄色面什么都点不动" perhaps they tapped effect that opens write wish page; the page itself in Fx window noninteractive -> cannot type. Then fix architecture: interactive fx UI must not live in Fx display window; put in main overlay host/present normal sheet. But if hitTest host swallowing, fix. We can say: 先判 yellow面 id，如果是写愿望页，最大根因是交互页面挂错纯显示 Fx 窗；修法迁移。

Q4:
异议: 圣诞 scale=1 only native; sonnet blur not proven same. WebView may have dpr=1/reset. 7100 count not root; texture memory.
根因排序:
1. Canvas backing store/CSS尺寸不匹配或 resize 后 width/height 重置但 transform/绘制未重做 -> 低分辨率拉伸（sonnet 最可能）。
2. WKWebView viewport/zoom/contentsScale/pageZoom 非1或未随旋转更新；dpr读取错误/被 cap 到1。
3. 原生精灵 `fmt.scale=1`（圣诞实锤）是另一条；若 sprite 在屏幕绘制点尺寸大于位图像素尺寸就糊。
4. 点阵粗糙/粒子过多导致LOD/降采样。
Minimal:
- 统一 `renderScale=min(UIScreen.main.scale,2)`；所有 canvas/offscreen/sprite 生成用实际 bounds*renderScale；resize时重设 backing store，reset transform, redraw; WKWebView `pageZoom=1`, `scrollView.zoomScale=1`, `contentScaleFactor=screen.scale`, viewport `initial-scale=1`. For native set fmt.scale=min(screenScale,2); share atlas; cap particle count; render text at 2x; if需要3x仅小区域/文字层，不做全屏。
- Budget: at scale2 full-screen ~21MB/frame buffer; 200-250MB allows ~4-5 layers; scale3 ~47MB per buffer, ~2.25x vs scale2, plus atlas from 2048 to 4096 4x if atlas grows. Recommend cap2 for full stage, 3 only transient text overlay not particle buffer. 
- Logs: `stage.render style=sonnet css=WxH dpr= device dpr renderScale canvas=WxH ctxScale pageZoom contentsScale`, `stage.resize old/new`, `stage.tex bytes`, `stage.ready`; native `xmas.sprite fmtScale px draw atlas`. 
Self proof: after rotation canvasW == round(cssW*renderScale); `renderScale=2`; visual sharp; memory under.

Need also mention Q4 "采样/过滤" maybe `image-rendering`, `filter`, `will-change`; `ctx.imageSmoothingEnabled`; WebGL `antialias`, pixelRatio. Minimal.

Need maybe include "自证面包屑设计" for each with exact log line format. Use concise code-like lines.

Need ensure answer "逐条回". Could be long but desired oververbosity 5; but problem demands thorough. We can be structured. Chinese.

Need not use markdown? We can use headings and bullet lists. Good.

Let's formulate.

Need maybe mention "释放 freeze 帧" vs "freeze 帧机制". In Q2 specify.

Need mention "主会话内无 >1.2s 日志行间隔" not equal no main thread blockage; logs may be buffered on background queue; a line interval <1.2 can still be 500ms. Need measure signpost and CADisplayLink hitch, not line gaps. Good point. Add.

Need mention "wall.scroll max=633.2ms" likely scroll hitch, not necessarily present. 93 vs 92 similar. "同期" may be unrelated; need same action/timestamp.

Need mention "p93 pop gap=762" if it includes crossDissolve, target <50ms invalid. If target <50 is tap-to-first-interactive? Must redefine. Good.

Need mention "主会话开头滚掉" but events at console open near end not rolled; mem absence is instrumentation. Add.

Need mention "xmas fps 0 because style sonnet, not Christmas; absence expected not evidence." Good.

Need "deck glyph cov/fb 0 despite deck host stage" maybe deck audit not triggered because host=stage not mini? But B1 is HomeWall miniPlayButton not stage? Wait p93 deck host=stage means control console deck? It may not include home wall miniPlayButton. So cov/fb at console deck does not cover home wall button. B1 conclusion "工厂没坏" from console glyph visible, but home wall miniPlayButton may use different factory or glyph id. Need mention. Also图三中央播放钮空圆 could be because HomeWall uses different path than MiniBarQuickRowView? Need verify. B1 said "主页墙 miniPlayButton 的视图栈". Need log instance host. Add: deck size=112/43 host=stage 是播放台/控制台，不是主页墙展开台？ Need not know. But evidence: `host=stage` only tells one deck, not mini button. Need add breadcrumb `deck instance=homeWallMini vs stage`, `glyph id/state`.

Need "pause字形无兜底" important: if current state playing, miniPlayButton expects pause; if factory returns nil due no fallback, final empty. But图四控制台 pause可见 from same factory? Could be different glyph config. Need instrument before blaming view stack.

Need "cov/fb自证只测工厂出口" correct but if absent entirely, not even factory. Need.

Need "A4 wall cache 160->128落码 but p93 wallcache 未出现 init rolled; can't confirm内存预算." Actually if wallcache init rolled, but subsequent memory 359 includes maybe cache; need log wallcache on memory pressure/scene and periodic.

Need "D 7100 一锅烩" not necessarily root; if share sprites, total count impacts CPU not texture memory. 3000+3000 separate计数 is management not visual. Need cap by device.

Need "图五糊是 sonnet WebView，不是圣诞，但 scale问题可能同族" good. We can say don't use圣诞实锤 directly判sonnet; separate.

Need "样片是 Three.js WebGL setPixelRatio(min(dpr,2)); 原生 CoreGraphics" Good.

Need include "样板先行" constraint: C4 height rollback values must not contradict sample. "回滚数值已备" but user says who changed; need verify sample spec first. If sample 54.9%, use that; otherwise don't guess. For C3 two pages same component per sample. For seam use home母版 per user added口径.

Need "全应用内存峰值 ≤450; 墙缓存120-180; 解码并发≤4." Our修法 Q4 scale2 likely within. Q1/Q2 no memory issue. Q3 no.

Need formulate final answer maybe:

```
结论：你们现在最危险的不是某个bug，而是探针不可信+单样本归因。先修A5，否则下一包仍无法切。
```

Then sections.

Detailed Q1 breadcrumbs:
```
wall.switch begin id=% gen=% from=% to=% off=%.1f origin=%.1f vel=%.1f fling=% 
wall.switch stopFling id=% reason=identity|layout dt=%.1f
wall.reanchor id=% anchorIndex=% originBefore=% originAfter=% valid=[%.1f,%.1f] clamped=% 
wall.render.audit id=% visible=% first=% last=% origin=%.1f min=%.1f max=%.1f drift=%.1f fling=% hidden=% 
wall.crossfade id=% showAt=% srcVisible=% srcFirst=% 
```
Ensure one switch id.

Q2:
```
rot begin id=% from=% to=% freeze=show
rot native id=% window=... stageFrame=... safe=... webFrame=... inset=...
rot web id=% inner=... dpr=... canvas=... css=... renderScale=... zoom=...
rot ready id=% t=... stableFrames=2
rot freeze hide id=% t=...
```
Check same id.

Q3:
```
fx.hit id=% pt=... hostFrame=... returned=% chain=% hostDecision=% interactiveCount=% 
fx.layer id=warmLight action=show/hide alpha=... interaction=...
fx.overlay id=... class=... frame=... alpha=... userInteraction=...
```
Need "chain" maybe a few names.

Q4:
```
stage.render style=sonnet phase=create css=390x844 dpr=3 cap=2 renderScale=2 canvas=780x1688 ctxScale=2 zoom=1 contentScale=3
stage.render phase=resize old=... new=... backing=... resetTransform=1
stage.tex bytes=... particle=... atlas=...
xmas.sprite id=... fmtScale=2 px=... draw=... atlasBytes=...
```

Need maybe answer "四个慢性问题根因排序" with 1/2/3.

Need mention "真机自证面包屑必须一刀切开": each line include ID, phase, decision; next log can grep. Add "不要只打完成行".

Let's now draft final in Chinese. Keep direct. Need no客套. We can say "先挑错". Use numbered.

Let's ensure no contradictions. In Q3 minimal fix: If host isUserInteractionEnabled false, children can't receive. Need design: host override hitTest returns nil unless whitelist contains point and child interactive. Keep host userInteractionEnabled=true but point(inside) false? Actually if point(inside) returns false then hitTest? Let's reason. UIView hitTest: if !isUserInteractionEnabled || isHidden || alpha<=0.01 return nil; if !point(inside) return nil? It checks point inside before subviews? It first checks self point inside; if false returns nil then no subviews? Actually hitTest implementation: if point inside self then traverse subviews; if no child returns self. If point outside self return nil. For full-screen host, point inside always true. Override hitTest in host: iterate whitelist interactive children; for each child convert point and call child.hitTest; return child if nonnil. If none return nil. Do not call super. This allows children even if host's `point(inside)`? Our override controls. Set decorative children userInteraction=false. Host itself can have userInteraction=true but hitTest returns nil. Good. If need pass-through to underlying views, returning nil from host allows hitTest to continue to sibling behind in same window if host is subview? Actually if host returns nil, superview can test other subviews. Good.

But if FxOverlayHost is full-screen subview added last, returning nil for non-whitelist passes through. Good.

Need mention "super.hitTest 非自身才交回" can swallow because super.hitTest may return host itself. Good.

For Q3 yellow face if write wish page interactive should not be in Fx window. Minimal: move interactive page to main window overlay/present; keep Fx pure display only.

Q4 memory calculation: Need be accurate: 390x844*2=780x1688=1.316M pixels *4=5.27MB, not 21MB. I earlier used MP wrong. Let's recalc: 780*1688 = 1,316,640 pixels (1.3MP). *4 bytes = 5.27MB. At dpr3: 1170*2532=2,962,440 pixels = 2.96MP *4=11.85MB. I mistakenly said 5.3MP/21MB for dpr2? Let's correct. For iPhone 390x844 CSS:
- dpr2 backing 780x1688 = 1.32MP = 5.3MB per RGBA buffer.
- dpr3 backing 1170x2532 = 2.96MP = 11.9MB per RGBA buffer.
If 5 buffers: dpr2 ~26MB, dpr3 ~59MB. Not huge. But if canvas includes full screen at larger iPhone 430x932 and multiple, still. For WebGL double/triple plus offscreen and mipmaps. Sprites textures: particle textures maybe small. 200-250MB stage budget. At scale3 2.25x pixel memory vs scale2. Atlas 2048² at RGBA = 4,194,304*4=16.8MB; 4096² = 67.1MB (4x). Correct. Need state these. This is important. I earlier wrote 21/47 for 780x1688? Wrong. Let's use correct numbers. For 390x844:
dpr2 5.3MB/buffer, dpr3 11.9MB/buffer. But multiple offscreen and accumulation? If using 3D Three.js WebGL: drawing buffer, depth, stencil, render targets. At dpr2 maybe 5.3 color + depth/stencil 8? Actually WebGL drawing buffer RGBA + depth/stencil maybe 4+4=8 bytes; ~10.5MB. dpr3 ~23.7MB. Render targets multiply. Still within. But if 3000 particles each with 256x256 texture? They share atlas. Need not overstate.

But "舞台纹理上限 200–250MB" They ask cost of scale2 or3. Need give tradeoff. For full-screen canvas at typical 390x844: dpr2 color 5.3MB per buffer, dpr3 11.9MB per buffer; 2.25x. At 430x932: dpr2 6.4MB, dpr3 14.4MB. If 4 offscreen buffers: 25 vs 58. Plus WebGL depth. Scale3 increases memory 2.25x, fill rate 2.25x and GPU bandwidth 2.25x; may cause fps drop. Scale2 is sweet. Use 3 only for small text/vector overlay. At 200-250MB budget, scale2 leaves room; scale3 risks if multiple canvases/snapshots. Native sprite atlas: if point sprite 64x64 at scale2 = 128x128? If atlas 2048² at 2x = 16MB; at 3x to fit same sprites atlas 3072² ~37.7MB or 4096² 67MB. Need use scale2.

Need adjust Q4 text accordingly.

Need maybe mention "contentsScale" on CALayer for native; for WKWebView, `contentScaleFactor` read-only? You can set? `WKWebView` is UIScrollView. `scrollView.contentScaleFactor`? Might not need. Use viewport/canvas. "contentsScale" for CALayer snapshots/offscreen. We'll mention.

Need "WebView画布 resize时的 scale reset": HTMLCanvasElement width/height reset clears context state, including transform. If code sets width but not `ctx.scale(dpr,dpr)`, drawing coordinates in backing pixels vs CSS, or vice versa, leads either blur/upscale. Need log.

Need "canvas backing store" exact.

Need maybe mention "UIWebView" no; WKWebView.

Need "解码并发≤4" not directly Q. Maybe B1 first image decode? Could be. We can mention in判读2: 首次布局触发条带封面解码，之前打印移出但封面解码未移出，可能卡。修法：预解码/降采样/并发≤4，首帧用占位。 But conclusion "卡点在viewDidLoad构建" might miss image decode on first layout. Good point. Add.

Need "控制台viewDidLoad构建 658pt内容链+条带封面+队列表+拍立得区" — if viewDidLoad only builds no images? Could be. But first layout after present triggers cover load. Need split. Use instrumentation.

Need "A3弹台分帧落码但失败" — 分帧 may add overhead if each chunk >16ms or uses `DispatchQueue.main.async` with layout thrash. Need stage budget: each chunk <8ms, no layout in loop, use precomputed frames; don't call layoutIfNeeded per chunk. Minimal: skeleton first, heavy sections after transition. Add.

Need "p93 mem absent" — If mem instrumentation gated by debug/test? Add unconditional high-water.

Need "present 02:36:40.262 -> p93 pop gap=762ms" If present at 40.262 and gap 762, then dismiss/pop at 41.024? Need no.

Need "wall.scroll max=633.2ms, 92 606.4" — This is scroll hitch not popup. It may indicate main thread busy before/after. Need compare same event. Good.

Need "图五横屏舞台 scene top 45%" Maybe WebView layout viewport still portrait height and `window.innerHeight` 844 while container landscape height 390, aspect? If canvas uses portrait aspect and scaled to width, scene top? Let's think: If CSS stage uses full width and height? Scene top 45% band with below black: Could be WebView content only occupies top because `WKWebView` frame height is half? Or CSS canvas height fixed 45vh due safe area. Need log frame. Not root native block. Good.

Need "歌词行左缘被切": likely container `contentInset` or transform translate from portrait; `scrollView.zoomScale` >1; viewport width set to portrait? If page zoom not reset after rotation, left clipped. Include in Q2.

Need "整幅点阵粗糙": dpr/canvas backing store issue, also in Q4. Q2 includes sonnet blur; Q4 handles.

Need perhaps rank Q4 for sonnet "canvas backing store low/reset" before "contentsScale". Good.

Need final answer not too long? The user asks detailed. We'll be moderately long but structured. The desired oververbosity 5, but complex. We can be ~3000-4000 Chinese chars? Need enough. Maybe 5000. Our final can be longer.

Let's start final:

```
总判：这份判读的硬伤是... 
```

Then "一、逐条挑错" with bullets. Need include all.

Let's draft carefully.

Potential issue: "pop gap 仪器含 crossDissolve 转场时长（约0.3s），即便扣除仍有约400ms" calculate 762-300=462 not 400. Mention arithmetic.

"deck size=112/43 host=stage" host=stage not homeWallMini; so B1 cov/fb absence not relevant? Mention.

"p93 mem absent despite console open" main session开头滚掉? But console open near end, mem breadcrumb if emitted on init early? If mem only at app launch, rolled. But if mem on console open should appear. Need phrase:若设计是在控制台打开时打，则缺失=探针失效；若只在启动打，则滚掉不能证明内存。需明确触发点。

"xmas fps 0"因为当时 sonnet，不是圣诞；0条不能说明圣诞性能。 Good.

"deck glyph cov/fb 0" if同工厂出口 should log on deck build; host stage built at p93 pop? It logs deck size host stage; cov/fb absent means not same exit or gated; cannot conclude final. Good.

"tap own 0" despite dismiss, instrumentation not in actual route. Good.

"风未开" cannot confirm; code deletion only.

"烟花未开" no sample.

"控制台宽：以音量行反推" could be wrong due volume slider intrinsic width. Need log.

"高度 658 = 屏高 77%" depends screen height; if device height not 855? Need log UIScreen. "用户斥谁让改这么大" need sample. Don't revert to 296/640 blindly if sample says other; user 10:39 says seam母版 etc.

Need "样片源码差异：Three.js setPixelRatio(min(dpr,2))" Good.

Need "歌单缝竖排标题溢出" exact: fixed frame 0.38H, title ≥15 overflow; minimal unify to home seam. Add.

Now final.

Need maybe include "修法翻车点" explicitly in audit items: B1 if只加pause fallback但仍被覆盖; C3 crossfade if source black; C4 if硬回滚数值违反样片; A3 if分帧每块仍layout; Q1 if只clamp origin不stop fling; Q2 if只缩短freeze; Q3 if把host interaction关死导致该点的按钮也点不了; Q4 if全上3x内存/fps翻车. Mention.

Let's formulate with markdown.

Good.
=== answer ===
总判：当前最大问题不是某个 bug，而是**探针不可信＋单样本归因**。多处把“日志没出现”直接当成“机制没发生”或“仪器位置正确”，这会误导下一包。先修 A5/最终渲染层探针，否则下一份日志仍切不开。

---

## 一、逐条挑错

### 判读 1：p93 只有 4 条
- “全部 0 条”不能统一解释。`xmas fps` 因当时是 sonnet，本来就不该有；`mem` 若设计为控制台打开时打，则缺失说明探针没执行，不是“没发生”；`deck glyph cov/fb` 缺失说明它没挂在最终按钮层，不能拿它证明工厂出口正常；`tap own` 缺失但 `dismiss r=dim` 已出现，说明 tap 归属探针没在实际 hitTest 路径上。
- `deck size=112/43 host=stage` 只证明 stage deck，不证明主页墙 `miniPlayButton` 实例。B1 的“工厂没坏、丢失在工厂之后”证据不足，尤其 pause 无兜底，而图三又是播放态期望 pause。

### 判读 2：pop gap=762ms
- 92 的 606.4ms 与 93 的 762ms 不是受控 A/B；单样本、不同窗口、可能不同缓存状态，不能直接判“移出打印后不降反升”。
- `pop gap` 若包含 crossDissolve，则目标 `<50ms` 的定义本身不成立；且 762−300≈462ms，不是约 400ms。必须先定义 gap 起止点：tap、present begin、viewDidLoad begin/end、首次 layout、首帧 commit、转场完成、可交互。
- “卡点在 viewDidLoad 构建＋首次布局”证据不足：首次布局触发的条带封面解码、字体、毛玻璃首次合成、分帧调度本身、约束爆炸、转场 completion 都可能。93 的分帧若每块仍触发 layout 或主队列串行，反而会把首帧推后。
- 修法翻车点：只做“viewDidLoad 分帧”但首帧仍同步 layout/解码，gap 不会降。应先上骨架/占位，重内容在转场完成后分段装载；每段 <8ms，禁止段内 `layoutIfNeeded` 全树。

### 判读 3：点外关闭 1 次 2ms
- 单实例只证明这一条 outside 路径生效，不证明所有子视图、透明层、overlay、跨 window 路径都通。
- 修法翻车点：把 `FxOverlayHost` 的交互一刀关死，会连带关掉祝福卡/写灯钮。必须白名单式 hitTest，而不是全局关交互。

### 判读 4：旋转 330ms、无 >1.2s 日志间隔
- “无 >1.2s 行间隔”不等于无卡顿：日志可在后台队列缓冲，330ms freeze 本身、以及 `landed` 后的 WebView resize/重绘都可能造成用户感知卡顿，且不计入 freeze→landed。
- 图五是 sonnet WebView：场景压顶部 45%、下方黑、歌词左切、点阵粗，指向 **WebView viewport/canvas backing store/旋转后 resize 不同步**，不能只归因原生布局阻塞。
- 修法翻车点：只缩短 freeze 时长会把黑/裁切更早暴露；正确是 freeze 释放绑定“内容首帧稳定”，不是固定 330ms。

### 判读 5：黑屏原点飞出
- `origin.x` 百万负值不必然等于空区，可能是虚拟坐标/transform；真正强证据是连续 `visible=0`＋`drift=4783`＋高 `pkv`＋`identityChanged=1` 同窗。但缺少顺序：identity 变更、rebase/reload、fling 停止、origin 越界、visible 归零谁先谁后。
- `visible=0` 也可能是隐藏期/交叉淡化期/替代表视图覆盖期仍在跑 audit。交叉淡化只遮 UI，不修状态机，这点你说对了。
- 修法翻车点：只 clamp origin 不停止 deceleration/display link，下一帧惯性又把它推出去；只做 crossfade 不保证源视图 visible>0，会从黑淡到黑。

### 判读 6：内存 285→359MB
- footprint 采样不是 peak；主会话开头滚掉不排除更高峰值；特效没开不能证明特效时段 ≤450；`wallcache` 初始化滚出不能证明 128MB 生效。必须周期高水位，且在控制台打开、旋转、切版式、特效开关时打点。

### 判读 7、8
- 特效投诉不在日志内，不能确认也不能排除；风未开，代码删除不等于 runtime 无其他 stop/cancel 路径。两者都只能标“未确认”。

### 代码审计挑错
- **B1**：证据不足。控制台同工厂字形可见，不等于主页墙 miniPlayButton 最终 layer 可见；pause 无兜底使“工厂出口正常”都可疑。探针应装在按钮最终渲染层：image 是否 nil、size、tint、template、layer.contents、子视图 z/alpha、毛玻璃/渐变覆盖、setImage 后下一 runloop 是否被刷新覆盖。
- **C1/C2**：图证只说明静态、单方向到达，不证明暗色、横屏、旋转后、滚动复用后到达。
- **C3**：两页胶囊式样不同已违反“样片同一组件”；交叉淡化只覆盖替代表/架视图，不能修模式 0 照片墙本体黑屏。
- **C4**：以音量行反推卡宽不可靠，音量行可能不是卡宽−24；`min(620,屏宽−20)` 可能因呈现上下文 bounds 不是全屏，或设备屏宽本身较小得出 300。必须日志打印 `UIScreen/window/view bounds、safeArea、calcW/calcH、实际约束`。高度 658 与 54.9% 冲突，回滚值不能凭记忆，必须以定版样片为准。
- **A1/A2/A3/A4/A5**：A1 单实例；A2 仅代码；A3 实测失败；A4 未确认；A5 在关键时刻失效。先修探针。
- **D**：`fmt.scale=1` 是原生圣诞实锤，但图五 sonnet 不是圣诞，不能直接互证；7100 一锅烩是资源管理问题，不必然是糊的根因。WebView 侧另有 dpr/canvas resize 问题。
- **缝**：头像/二维码缺失和两套缝实现是实锤；歌单缝竖排标题固定帧高导致溢出叠印也实锤。用户已定“以主页缝为唯一母版共用实现”，不要再分别修两套。

---

## Q1 排版切换黑屏卡死

**根因排序**
1. 模式/identity 切换时未先停 fling/deceleration，rebase/reload 后旧速度仍在旧虚拟坐标上跑，导致 origin 越界、visible=0。
2. 隐藏期/替代表期间墙的 display link/惯性/audit 未暂停，交叉淡化只遮 UI 不修状态。
3. 坐标换算或 audit 记录时机问题，使负百万 origin 不等于实际空区；但前两条仍需先修。

**最小修法**
- 进入 `wall.state=modeSwitching`：立即停止 deceleration、取消惯性/display link、禁止 bounce。
- 在 identity/reload/rebase 前后做重锚：以当前可见 item 或锚点 index 重置虚拟 origin，按新 contentSize clamp 到合法范围；切换完成且 `visible>0` 后才允许 crossfade。
- crossfade 源必须是上一张有效快照或 `visible>0` 的源视图；禁止在源 `visible=0` 时淡化。
- 修法翻车点：只 clamp 不 stop；只 crossfade 不重锚；切换中仍允许手势。

**面包屑**
```text
wall.switch begin id=... mode=...->... gen=... off=... origin=... vel=... fling=...
wall.switch stop id=... reason=identity|layout dt=...
wall.reanchor id=... anchor=... originBefore=... originAfter=... valid=[min,max] clamped=...
wall.render.audit id=... visible=n first=... last=... origin=... min=... max=... drift=... fling=...
wall.crossfade id=... srcVisible=n srcFirst=... show=...
```
下一份日志必须能看到：切换前 `fling=0`，reanchor 后 `clamped=0`，crossfade 前 `visible>0`。

---

## Q2 横竖屏旋转卡顿

**根因排序**
1. freeze 释放固定 330ms，但 WebView/CSS/canvas 的旋转 resize 和重绘在 `landed` 后异步发生；用户看到的是旧画布裁切/拉伸/黑底。
2. 横屏舞台容器/WebView frame 未满屏，或 `contentInsetAdjustment`/safeArea/zoomScale 残留，导致场景压顶部、歌词左切。
3. canvas backing store 未按新 CSS 尺寸×dpr 重建，或 resize 后 width/height 重置了 context 但未重设 transform/重绘，点阵粗糙。
4. 原生主线程短 hitch 不是主因；但需用 signpost 排除。

**最小修法**
- 旋转期间保持 freeze；原生布局先把舞台容器/WebView 设到全屏可用区，`scrollView.contentInsetAdjustmentBehavior=.never`，清理 zoom/inset。
- 显式通知 JS 新尺寸；canvas 重建 backing store：`round(cssW*renderScale)`、`round(cssH*renderScale)`，重设 `ctx.setTransform(renderScale,0,0,renderScale,0,0)` 后重绘。
- freeze 释放条件改为：native layout 完成＋WebView resize 完成＋JS `stage.ready`＋至少 2 个稳定帧；不要按固定 330ms。
- 修法翻车点：只缩短 freeze；只改原生 frame 不改 canvas；旋转中允许用户滚动触发旧惯性。

**面包屑**
```text
rot begin

---
## 补答（Q3/Q4，第一答在 Q2 面包屑处被 16000 token 上限截断，同轮补齐）
Q3  
结论：黄色面最可能是 `showBless` 的祝福卡（深棕渐变＋琥珀边，视觉发黄）及其全屏容器，不是 Fx 独立窗；Fx 根视图已禁用交互，问题在主窗 `FxOverlayHost91` 的 hitTest 把“大容器自身”交回，且被动识别器反复触发弹卡，卡出现后吞掉后续点击。  
剩余吞点路径：1）`super.hitTest` 返回宿主自身未彻底剔除；2）返回祝福卡背景/推荐卡/写灯钮等全屏或大容器自身（非控件）即吞；3）只判 hidden/alpha/interactive，未判 attached、transform、实际 pointInside；4）卡片全屏遮罩 `isUserInteractionEnabled=true`；5）展示中未防重入，点灯体反复 showBless；6）透明容器可交互但无实际按钮；7）识别器不取消触摸，但弹卡后新视图接管命中。  
最小修法：host hitTest 改白名单，只返回明确按钮/卡片内可点控件；显式 `if hit === self || hit === subview || hit is FxOverlayHost { return nil }`；容器只开子按钮交互，祝福卡背景不接 hit，卡外点击关闭且穿透；`showBless` 防重入，展示时禁用识别器或 delegate 过滤“命中交互控件不弹”。  
自证面包屑：hitTest 打点 `point/candidate.class/hidden/alpha/interactive/frame/hit.class/hit==self`；点击空白应返回 nil 并到达底层；按钮返回按钮；showBless 计数≤1；View Debugger 确认黄面层级；录屏验证空白穿透、按钮可点、卡外关闭。

Q4  
WebView 歌词侧先查：`window.devicePixelRatio`、`renderer.getPixelRatio()`、`canvas.width/height` 与 `clientWidth/Height`、`gl.drawingBufferWidth/Height` 是否一致；`setPixelRatio(min(dpr,2))` 调用时机及 resize/orientation 是否重设；`renderer.setSize(w,h,false)` 是否同步 CSS 尺寸；是否有 `zoom/transform: scale()`、CSS 拉伸、低分辨率离屏 canvas、截图/纹理源 1x；WKWebView 外层 layer `contentsScale` 是否被改成 1；CSS filter/opacity/阴影是否触发低精度栅格化。  
原生栅格代价：内存约按 scale² 增，1→2 为 ×4，1→3 为 ×9；3x 最清晰但峰值和光栅化耗时高，舞台纹理 200–250MB 下仅适合小图/分区/临时，2x 是折中且 3x 屏仍明显改善。最小修法：原生 `fmt.scale = min(UIScreen.main.scale, 2)`，超大图分块/裁剪/下采样并缓存释放；WebView 统一 init+resize 调 `setPixelRatio(min(dpr,2))`，校正好 canvas buffer 与 CSS 尺寸。自证：原生打印 `UIScreen.scale/format.scale/cgImage 宽高 vs point`；WebView 注入 JS 打印 dpr、canvas、client、drawingBuffer、pixelRatio；截图像素对比；Instruments 记录峰值确保舞台纹理≤250MB。
