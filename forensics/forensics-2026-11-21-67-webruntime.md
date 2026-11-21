# 取证：(67) 网页运行是否真被调用（2026-11-21，只读）

对象：release-67（2e42c95）。起因：Miller 真机装 (67) 后选样式感觉仍是原生在跑，截图显示选择器每行徽标均为「原生」、当前选中「回环」✓ 亦为原生，行内橙字「网页」为另一元素。

## 一、运行位缺省：全缺省原生（设计如此，非故障）

- 存储：`StageRuntimeStore`（Sources/Native/Features/Stage/StageRuntimeStore.swift:13-33），UserDefaults 键 `folia.stage.runtime67.<styleId>`，值 `native`/`web`。
- 读取（同文件 :20-21）：键不存在或值非法 → `.native`。**没有任何播种/迁移代码**：全仓 `git grep setRuntime` 只有一个调用点（选择器切换钮，见第二节）；(66) 从未写过这批键。故首启与从 (66) 升级完全一致——17 式初值全为原生。
- 可切范围（Sources/Native/Features/Stage/LyricStageProtocol.swift:261-263）：`hasWebRuntime = id ∉ {tuning, corridor, afterglow, petconcert}`，即注册表 21 式中 17 式可切；自有四式恒原生、不读存储。例外：町景 machi 虽 hasWebRuntime=true，但 isLocked → 切换钮不出现（Picker :207）。

## 二、选择器点按语义（StageStylePickerViewController.swift）

行内三元素，语义各异（截图与代码逐项吻合）：

| 元素 | 代码 | 语义 |
|---|---|---|
| 边框徽标「原生」/「网页运行」 | :184 UILabel，纯展示 | **当前**运行位：isWeb→「网页运行」（橙），否则「原生」（绿）。不可点 |
| 橙字「网页」/「原生」 | :211-218 UIButton，:213 钮面=**目标**运行位（当前原生时写「网页」） | 点它才切换：handleRuntimeTap（:248-258）→ 取反 → StageRuntimeStore.setRuntime 持久化并落 `styleruntime` 面包屑 |
| ✓ | :236-238，`style.id == activeStyleId` 时出现 | 「当前舞台正在演的样式」，与运行位无关。截图中回环 ✓＋徽标「原生」＝回环是当前样式且以原生运行 |

点按路径：
- **点「网页」钮（非当前样式）**：只翻该式运行位＋刷新本行徽标（:255-257），不打开舞台、不影响正在演的样式。
- **点「网页」钮（当前样式）**：翻位后经 onPickRuntime（StageViewController.swift:1862-1867 / 2002-2007）关选择器并 applyNativeStyleSelection → swapRenderer 按新运行位立即重呈现。
- **点样式名（整行）**：didSelectRowAt（:329-333）——isNativeAvailable 的 17 式一律走 onPickNative（名字与运行位无关），落点 swapRenderer（StageViewController.swift:1154-1167）在 :1162 按 `StageRuntimeStore.isWeb(to)` 分流：网页位→swapToWebRenderer，原生位→原生换装。**即行点选尊重已设的运行位，但行点选本身永不改变运行位。**
- 页头说明（:45）与上述一致：「点样式名即以当前运行方式打开」。

**对 Miller 截图的判读**：截图时点全 17 式徽标均为「原生」＝该机上没有任何一式被切到网页位。若他点过橙字钮，对应行徽标应已翻为橙色「网页运行」且日志必有 `styleruntime rt=web`（见第五节）——代码中不存在翻位后被自动改回原生的路径。最可能情形：他点的是样式名（行点选），而运行位从未被那个小橙字钮翻过；该钮钮面写的是目标态名词、无开关形态，极易被当成标签错过。此为 UI 可供性问题，非调用链故障。

## 三、舞台挂载链（运行位=网页时）

入口三路殊途同归，均经 StageViewController：
1. 开台初始：resolveInitialStyle（:1036-1041）→ mountRenderer（:1055-1061）isWeb → mountWebRenderer（:1202-1213）。
2. 换装：swapRenderer（:1162-1167）isWeb → swapToWebRenderer（:1218-1237）。
3. 三击轮换/每首歌随机：共用 applyNativeStyleSelection（:434-442）→ swapRenderer，同 2。

链路：armWebStyleProof（武装 style-guard，:1245-1253）→ embedWebView（WebView 入 rendererContainer、bringSubviewToFront、关交互，:1258-1273）→ alpha=0（有原生垫底时）→ isEmbeddedInStage=true → pushSnapshot＋pushVisual(lyricMode=styleId)（桥 WebEffectBridge.swift:1473-1486，同时记 lastDesignatedWebStyle 并落 `webfx.push`）→ armWebFade（:1279-1300）→ 回执或超时 → completeWebFade（:1309-1329）网页层 0.35s 淡入、完成后拆原生垫底。

前置条件与回执：
- 首帧回执：网页侧画出指定样式第一帧后 postMessage `styleFrame` → 桥处理（WebEffectBridge.swift:1796-1803）落 `webfx.frame` 并回调 onStyleFrame → handleWebStyleFrame（:1302-1305，须 styleId==webEmbedStyleId 且淡换未结算）→ completeWebFade(via:"ack")＋finishStyleProof(via:"web-frame")。
- 超时：页面已 loaded 时 1.8s、未 loaded（冷启）时 6s 并落 `webfx.cold`（:1288-1292）。
- 看门狗：网页进程被杀 → webViewWebContentProcessDidTerminate（WebEffectBridge.swift:1940-1946）嵌入态落 `webfx.kill` → 退避 reload → didFinish 推快照＋嵌入态补推指定样式 `webfx.repush`（:1894-1897）。

### 静默回退点清单（重点项）

**结论先行：会话内不存在「回执失败→静默切回原生渲染」的回退。** 逐点核完如下：

1. **回执超时 ≠ 回退原生**：超时落 `webfx.ackto` 后照样 completeWebFade(via:"timeout") 把网页层淡入（:1293-1297、:1317-1319）。若网页页本身坏死，用户看到的是空白/黑的网页层，而非原生——且界面上无任何提示，只能靠日志区分 via=ack/timeout。
2. **pushVisual 在页面未 loaded 时被 dispatchToJS 静默丢弃**（WebEffectBridge.swift:1595），但 pushVisual 已先记 lastDesignatedWebStyle（:1481），didFinish 时嵌入态补推（:1894-1897），此洞已封。
3. **style-guard 的回退只跨启动**：pending 未证明且进程被杀 → 下次启动 runLaunchStyleGuard 把 currentStyleId 重置为默认经典式（StageStyleStore.swift，面包屑 `stage style-guard reset … reason=pending-unproven`）。注意它重置的是**样式选择**、不是运行位；且网页式的证明可由 frameStep 的 frames+lyrics/window 路径结算（StageViewController.swift:2851-2861），不全依赖回执。
4. **handleWebStyleFrame 的 guard 丢弃**：回执 styleId 与当前嵌入式不符、或淡换已结算时静默忽略（:1303）——设计内行为。
5. **swapToWebRenderer 同式短路**：webEmbedStyleId 已是目标式时只补 pushVisual、不重挂不重淡（:1219-1222）——设计内行为。
6. 真正的「静默原生」只有第 0 号点：**缺省原生＋行点选不改运行位**（第一节/第二节）——用户不点橙字钮，网页层永不被调用，且全程无任何「你现在是原生」的主动提示（仅舞台样式胶囊在网页位时加「· 网页运行」后缀，:1355；原生位无后缀）。

## 四、冲突面：网页宿主 vs 原生渲染器同挂载

- 同级同容器：WebView 与原生渲染器 view 同为 rendererContainer 子视图（embedWebView :1260-1272，addSubview＋bringSubviewToFront → 网页层在容器内最上）。
- 原生→网页：原生渲染器留作垫底（webBackingRenderer），网页层 alpha 0→1 淡换，completion 才 unmount 垫底（:1320-1328）。重叠窗口内最上层是网页层——不存在「网页已挂却被原生盖住」。
- 网页→原生：原生层在网页层之上装配（:1168 注释口径与 addSubview 顺序一致），网页层延后 0.5s detach，带代次校验防误拆新一轮淡换（:1182-1192）。
- 网页→网页：同一 WebView 内页面自切，alpha 保持（:1215-1222）。
- 单例 WebView：嵌入宿主与全屏网页舞台宿主共用 WebEffectBridge.shared.webView；jumpToWebStage 前先 detachWebEmbed 防状态串扰（:1761-1766）；detach 复原交互/布局标志（:1344-1347）。
- 残余（非视觉冲突）：淡换 completion 被代次 guard 拦截时，垫底原生渲染器可能滞留挂载在不透明网页层之下继续渲染（耗电/占内存、不可见），下轮换装时才被清；ack 在网页→原生 0.5s detach 窗口内迟到会把已降位的 webView alpha 置 1，但其在原生层之下、随即被 detach，无视觉产物。**未发现**「网页层已挂载、alpha=1、却被原生层永久遮盖」的路径。

## 五、面包屑判读表（Miller 导日志后按此对）

| 面包屑 | 出现条件 | 判读 |
|---|---|---|
| `styleruntime style=<id> rt=web` | 点橙字钮翻位成功（StageRuntimeStore.swift:27） | **没有此行＝运行位从未被切到网页**，后续一切免谈 |
| `swap.begin … to=<id>`＋`webfx.mount style=<id> via=swap` | 换装走网页分支（Stage :1235） | 原生侧确实进了嵌入挂载 |
| `webfx.mount style=<id> via=initial` | 开台即网页式（Stage :1211） | 同上（初始路） |
| `est.src style=<id> est=web` | 挂载同刻（Stage :1212/:1236） | 辅助佐证 |
| `webfx.push style=<id>` | pushVisual 下发指定样式（Bridge :1483） | 指令已发（页面未 loaded 时 JS 投递被丢、靠 repush 补） |
| `webfx.frame style=<id> dt=<ms>` | **网页侧回 postMessage styleFrame**（Bridge :1802） | **唯一硬证据：网页真收到指定式、真画出第一帧**。原生代码无任何路径能伪造此行 |
| `webfx.fade via=ack` | 回执放行淡换（Stage :1313） | 网页层经回执淡入，与 frame 行成对出现 |
| `stage style-guard proven style=<id> via=web-frame` | 回执结算守卫（Stage :1144） | 同上佐证 |
| `webfx.ackto style=<id>`＋`webfx.fade via=timeout` | 回执未在 1.8s（冷启 6s）内到（Stage :1295/:1313） | **回退嫌疑行**：网页层被超时强行淡入，未证明出帧——页面坏死时用户看到的就是这条路径 |
| `webfx.cold style=<id>` | arm 时页面未 loaded（Stage :1291） | 冷启慢，不必然失败；看后续 frame/ackto |
| `webfx.kill style=<id>` → `webfx.repush style=<id>` | 进程被杀→重载补推（Bridge :1946/:1895） | 看门狗工作过；repush 后应再见 frame |
| `stage style-guard reset from=<id> … reason=pending-unproven` | 下次启动守卫重置（Store） | 上次会话该式未证明存活被杀，样式被重置回经典（运行位不动） |
| `stage fallback to web: …` | jumpToWebStage 全屏网页舞台（Stage :1767） | 是旧全屏宿主路径，**不是**台面嵌入，勿混判 |

判读顺序：先找 `styleruntime rt=web`（有没有切）→ `webfx.mount`（有没有挂）→ `webfx.frame`＋`webfx.fade via=ack`（有没有真出帧）→ 若只有 `webfx.ackto`＋`via=timeout` 而无 frame，则是「挂了但没证明出帧」。

## 六、总结论

调用链本身完整、无「撞车」：缺省原生（设计）、翻位靠行内橙字小钮、行点选按已设运行位分流、嵌入挂载/回执/看门狗均有代码实证。Miller 截图与「仍是原生」的体感，与「运行位从未被翻到网页」完全自洽；会话内无静默回退原生的路径，唯一的无声失败模式是回执超时后网页层被强行淡入（via=timeout，日志可判）。最终定性待其 (67) 桥日志按第五节判读表对账。
