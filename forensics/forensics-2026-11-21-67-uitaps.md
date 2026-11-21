# (67) 真机三投诉取证 — 封面点动 / 长按白环 / 细条与详情页进度条

取证对象：release-67（出包提交 1abbe98，报告提交 2e42c95）代码 + Miller 三段录屏逐帧核验。
帧与统计产物：`~/workspace/folia-deploy/scratch-forensics-1121/`（v1/v2/v3 全帧、逐帧差分 `*_diffs.npy`、关键帧 hires/、ring_zoom.png、v3_dragstrip.png）。

## 录屏映射（先说清）

- **V1 与 V2 是同一段录屏**：文件 md5 不同，但逐帧抽样拼图 sha256 完全一致、逐帧差分数列逐值相同（均值 11.20、max 82.78、冻结帧分布一致）。内容为**主页墙（WallPrototype 拼贴墙）**：点卡展开、拖墙、底部细条与白环全在这一段里 → 对应投诉 A、B、C①。
- **V3**（23.9s）：前 ~20s 是网格墙（歌单页）+ 底部点播台形态切换，20.8s 起进入歌曲详情页（舞台页，《想》—刘弈画，镜台·网页运行），对应 C①（细条切换实况）与 C②（详情页进度拖动）。
- 版本注记：V3 第 1 帧顶部有 (68) 交付通知横幅，录制时间在 (68) 交付之后；但 C② 涉及的舞台进度链（StageProgressDriver / stageSeekPanned / setStageProgress）在 (67)→(68) 间未被触碰（(68) 只动状态可视化与全宽条出样、缺省关），本报告结论对两版同成立。

---

## A. 封面点动：飞的是整卡，不是封面图；回程有硬切

### 视频证据（V1/V2）
- 展开一例：t=4.17–4.63s，连续 14 帧帧差平滑衰减 45.75→27.18→24.36→18.94→12.27→8.98→6.88→5.94→3.68→1.35→0.80→…→0.64，无冻结帧——0.45s 弹簧飞行在场。飞行对象肉眼可辨为**整张卡连同标题文字一起变大**（4.30s 帧：右侧手掌卡的 "Calendar Girl" 标题与手写字随卡同步放大），不是封面图单独放大。
- 回程/切卡硬切两例：
  - t=5.50–5.80s 一段运动帧差 77.18→82.16→79.15→70.09→55.12→46.27→60.79→47.32→**31.64→0.47**：末帧差一帧内从 31.64 掉到 0.47，弹簧尾巴被截断式收尾，不是自然减速落定。
  - t=6.23s **单帧帧差 82.78**（全片最大），下一帧即回落 7.31：6.20s 帧里手掌卡还是展开态，6.27s 帧已收回且整墙换位——展开卡的收回在 1 帧内完成，全程无飞行、无弹簧。

### 代码位置（WallPrototypeViewController.swift，release-67）
- `handleWallTap`（约 L3046–3050）：点卡时 `heroSnapshot = sourceCell?.snapshotView(afterScreenUpdates: false)`——快照对象是**整个 cell**（WallPosterCell = 封面图 + 标题 + 副标题 + 阴影容器，展开态还含播放/红心/进度控件），不是封面 imageView。
- `HeroFlight67`（L3206–3224）：`fly()` 只有一句 `view.frame = targetFrame`——把整卡位图从源帧拉到目标帧。源/目标宽高比不同（小卡 vs 展开矩形），位图被非等比拉伸；位图分辨率是小卡的像素尺寸，放大 ~2–3 倍必然发糊。
- `animateHeroExpansion`（L3107–3170）：飞行与布局弹簧共用 0.45s / damping 0.86 的 UIViewPropertyAnimator（与 4.17–4.63s 实测窗吻合）。
- `finish()`（L3220–3223）：`removeFromSuperview` + 被藏真卡 `alpha = 1`——**硬换**，无交叉淡化。展开落定时真卡带着控件与（可能刚换上的）高清封面一帧内替换掉拉伸位图；收起落定同理。
- 身份变化分支（L3153–3167）：`reloadData + layoutIfNeeded` 先行，**布局本体瞬时落定**，只有快照独飞；`makeHeroFlight67` 任一输入缺失（快照 nil / 源=目标 / 减动效）即返回 nil → **连快照都没有，整次展开/收起就是一帧跳变**。6.23s 的单帧 82.78 与此分支（或飞行中被下一击 `stale.finish()` 瞬时收尾，L3113–3116）形态一致。

### 根因定级：已定级
- 「整个框慢慢放大」是实现构造本身：飞的对象从第一行代码起就是整卡快照，封面图层从未单独飞过。Miller 的描述与代码逐项吻合。
- 「回归正常尺寸卡一下」：主因 = `finish()` 的无淡化硬换 + 身份变化分支的布局瞬时落定；个别次（6.23s）飞行层根本没建、收回一帧完成。具体哪一回程走了哪条分支，需桥日志 `wall.hero from=… to=…` 有无对账（一行即可判：有 = 有飞行层，无 = 直跳）——此点为候选待日志，不影响主因定级。

### 修法要点
1. 飞行对象换成封面图本身：用被点卡 imageView 已加载的 UIImage 新建 UIImageView（.scaleAspectFill + 圆角 8），源帧取 imageView 在 VC 坐标系的实际帧，目标帧取展开卡封面区帧；标题/控件不进飞行层。
2. 落定改交叉淡化：真卡先 alpha=1 就位、飞行层 0.1–0.15s 淡出再摘，消灭硬换帧。
3. 收起反向同路：从展开卡封面图飞回小卡封面帧；身份变化分支也要为封面保留飞行层（布局可瞬时，封面不可瞬时）。

---

## B. 长按小圆点/白环：宠物 4 秒开启手势的进度环，还活着

### 视频证据（V1/V2）
- 白环在整段 8s 内反复出现在屏幕底部中央一带（0.70s、0.83s、1.10s、1.67s、4.30s、5.20s、6.20s、6.27s 帧均可见），位置随按压点小幅移动，弧段填充程度各帧不同。
- 放大定格（ring_zoom.png，4.30s）：直径 ≈81px（720 宽帧）≈ **44pt**，**暗色圆盘 + 白色粗描边圆环**，压在墙卡与橙色细条上方。

### 代码位置
- 视图本体：`StageCycleProgressRingView`（StageStyleCycleBag.swift:135–193）：44pt、背景黑 0.35、白色 3pt 描边、strokeEnd 线性填充、弹簧缩放入场——与视频逐项吻合，全仓无第二只长这样的视图（TouchGlow62/TransitionAnim62 的环是紫色、舞台专用、缺省关，排除）。
- **(67) 里唯一的实例化路径**：`MiniBarPetOpenGesture`（MiniBarPetStage.swift，(60) 第 8 条）——点播台宠物关闭态下，长按台身空白域满 4 秒重开宠物的组件：按下 0.22s 后在按压点出环、按 4s−0.22s 线性填满、触发补满淡出；漂移 >12pt 或抬手撤环。
- 舞台侧的原生长按轮换接线已在 (61) 整组摘除（StageViewController.swift:330 注释自证），类本体因宠物手势共用而保留——这就是「说了删却还在」的来历：删的是舞台接线，不是这个类。
- 接线点共三处宿主：WallPrototypeViewController.swift:615、HomeWallViewController.swift:1227、StageViewController.swift:2088（均 `petStage.attachOpenGesture(to: bar)`）。
- 出现条件：`StickerSettings.miniPetsEnabled == false`（宠物关）时才武装。Miller 机上宠物为关态，他在细条/台身上按压（与 C① 的反复点按是同一串动作）即点亮此环——B 与 C① 是同一次操作的两面。

### 根因定级：已定级（视频形态 + 代码唯一路径双合）

### 整删清单（供主聊天定粒度）
- **方案一·只删视觉**：删 MiniBarPetOpenGesture 内的环创建/呈现/撤除（pressBegan 的 DispatchWorkItem 出环段、pressMoved/pressEnded/handleRecognizer 的 ring 调用），`StageCycleProgressRingView` 类随之无引用、可整类删除。4s 长按功能本体（识别器 + StageCyclePressObserver + 触发落点）保留：宠物关时仍可长按台身 4 秒重开，只是全程无视觉反馈、仅触发瞬间有震动。影响：无反馈的隐藏手势更难被发现，但 Miller 已明确不要这个环。
- **方案二·整组删**：再删 MiniBarPetOpenGesture 类、`MiniBarPetStage.attachOpenGesture`（MiniBarPetStage.swift:1461）与三处宿主接线、`StageCyclePressObserver`（(67) 内仅此组件在用）。影响：宠物关态下失去「台上长按 4 秒重开」的就地恢复路径，重开只能走设置开关（同源键 SettingsStore.miniPetsEnabled / StickerSettings.miniPetsEnabled 本体不动，不受影响）。
- **不可误删**：`StageStyleCycleBag`（洗牌袋本体）仍被舞台三击轮换在用，只能删同文件里的环与观察器两件。

---

## C①. 歌单/墙面点播台细条点不动

### 视频证据
- V3（网格墙宿主）：细条点按**有成功记录**——t=0.97–1.27s 底部带连续 10 帧变化（帧差 8.74→16.29→…→2.17）为展开弹簧；t≈6.23s 再变（距展开 ≈5.3s，与 5s 无操作自动收起时序吻合）；t=14.80–15.07s 再次展开。即同一手势在该宿主、该会话里是通的。
- V1/V2（拼贴墙宿主）：8s 内细条始终保持收起态（橙线 + 圆点），其间底部中央反复出现 B 的白环（按压确实落在台身域内），但**没有任何一次展开弹簧序列**；结尾（7.33s 后）底部出现的标题条是墙卡本体，不是台展开。

### 代码位置（WallPrototypeViewController.swift 为主，三宿主同构）
- 收起态点按的正路是存在的：`miniBarCollapsedTapRecognizer`（L908–911）独立无 require 链，`miniBarCollapsedTapped`（L1156 附近）直接 `expandMiniBar()`；启停由 `setMiniBarForm → syncMiniBarTapRecognizers`（L1185–1189、L1428）随形态同步：收起态只开它、关掉单击/双击链。命中带由 `MiniBarHitView.point(inside:)`（MiniBarHitView.swift）纵向 ±14pt 扩到 44pt；台身底部锚 safeArea −10pt，几何不悬空。
- 细条可见面被 `miniSeekHit`（底部 20pt 带）整覆，其自带 seekTap（L800–803）在收起态由 `miniSeekTapped` 的 `!miniBarCollapsed` 守卫静默返回——不拦截 collapsedTap（两者同触并发识别），但用户视角是「点上去先被 seek 通路吞了一口」。
- **已知的失同步前科**：(63) 第 2 条专门加了几何自愈（miniBarTapped 内 `heal=geom`，三宿主都有）——形态标志与几何高度曾在真机失同步，自愈逻辑的存在即为此事的自证。失同步（标志=展开、几何=细条）时：collapsedTap 被 sync 关掉，点按落进展开态单击链，须等双击+0.55s 长按双落空（约 0.35s+ 无任何反馈）；期间连点第二下即被双击识别器接走（miniBarDoubleTapped → 进详情页），不展开台。用户感知即「点不动」。
- 宠物层排除：MiniBarPetStage.hitTest（MiniBarPetStage.swift:905）只认领宠物本体/气泡，余皆放行；快捷行浮层未示时 isHidden + hitTest 返回 nil（MiniBarQuickRowView.swift:417、426），均不挡细条。

### 根因定级：候选待日志
- 同步态下代码路径成立、且 V3 实证同手势可通；V1 宿主点不开的最可能机制是**形态标志/识别器启停失同步**（有 (63) 前科与自愈代码为据），次选是命中带上半段（+14pt 区）与墙面手势的边界个案。判读只需 Miller (67) 桥日志两行：`minibar.form host=wallproto collapsed=… recog=…`（三位启停位）与有无 `minibar.form host=wallproto heal=geom`——recog 位与 collapsed 位对不上即定案。

### 修法要点
1. 识别器启停不再只挂在 setMiniBarForm 一条路上：展开/收起的每个入口（含边沿复位、viewWillAppear）后强制按当前几何重同步一次（几何为准，不以标志为准）。
2. 收起态点按零等待：collapsedTap 之外，给细条命中带再加一层与形态无关的兜底——高度 ≤20pt 时任何落在台身的点按先走展开判定（把 (63) 自愈从 miniBarTapped 前移到识别器分发前）。
3. 排查时先落一行面包屑：细条点按命中/未命中各记一条（宿主 + 标志 + 几何高 + recog 三位），下次真机一抓即定级。

---

## C②. 歌曲详情页（舞台页）进度条拖动闪帧很卡

### 视频证据（V3）
- 详情页段（t=20.80s 进入，舞台条为底部胶囊、轨在条底内缘）：无触摸播放期（21.33–22.37s）轨道带逐帧差 ≤0.10（静止基线）。
- 拖动窗 t=22.40–22.73s：底部带连续 10 帧帧差 3.68/3.28/6.42/5.40/5.05/4.81/3.99/3.85/2.95/2.14——整窗不落定、持续翻动，与基线差两个数量级；t=23.10–23.30s 还有第二次短触（1.88/1.60/0.95…）。填充/圆点在拖动中被两路数值轮流重绘的观感，与 Miller「闪帧很卡」描述一致。

### 代码位置
- 进度唯一写点 `setStageProgress`（StageViewController.swift:2399–2406）：改填充 transform + 圆点约束 + 主题层 fraction。
- 写点有两个调用方在拖动期**并发**：
  1. 拖动方：`stageSeekPanned`（L2558–2597）.changed → `setStageProgress(手指 fraction)`；seek 只在 .ended 才发（performSeek），拖动全程引擎位置不变。
  2. 驱动方：`StageProgressDriver`（Player/StageProgressDriver.swift）是 CADisplayLink 逐帧驱动，fraction 变化 >0.0004 即回调；StageViewController.swift:537–539 的接线是 `progressDriver.onFraction = { self?.setStageProgress(fraction) }`——**没有拖动态守卫**。播放中该回调近乎逐帧触发，写的仍是引擎播放位置 fraction。
- 结果：拖动期间填充/圆点以显示帧率在「手指位置」与「播放位置」之间轮流被写——闪帧；圆点一半帧数停在旧位置——拖起来卡顿、不跟手。
- **对照组（同仓现成正解）**：墙台同一驱动的接线带守卫——WallPrototypeViewController.swift:481–483 `if let bar…, !self.miniSeekDragging { setMiniProgress }`。舞台台独缺这一行，是 (13.4) 抽共享驱动后两宿主接线不一致留下的缺口。
- 附带一跳：松手 seek 后驱动锚点靠「漂移 >0.25s 连续 2 帧重锚」纠正（StageProgressDriver.swift stepFrame），落点后还会有一次小幅回跳收敛，与拖动闪帧叠加。

### 根因定级：已定级（代码双写点实证 + 视频拖动窗/基线对照）
- 不是每帧重建视图（写点只改 transform 与一条约束，本身很轻），不是 seek 风暴（seek 只在松手发一次）；主因就是驱动回调缺拖动态守卫的双写打架。WebView 特效（镜台·网页运行）在同页确实占主线程/GPU，是次要背景负载，但基线期轨道带帧差 ≤0.10 说明它不是闪帧来源。

### 修法要点
1. 舞台接线补守卫，与墙台对齐：`onFraction` 内 `guard !stageSeekDragging else { return }`（stageSeekDragging 已存在于 stageSeekPanned 的状态管理中，现成可用）。
2. 拖动结束（.ended 发 seek 后）到驱动重锚完成之间加一小段「落点保持」：以 seek 目标 fraction 为准冻结驱动写点，直到 rawPlayhead 进入目标 ±0.25s 或超时 300ms，消灭落点回跳。
3. 回归自证：拖动期落一行面包屑记驱动被守卫挡下的次数（可选），真机拖一次即可判读。

---

## iOS 适配自查（本取证涉及面）
- 横竖屏：三条投诉均发生在竖屏录屏；细条命中带/台身锚点为竖屏定版几何（横屏同宽居中），本报告结论不依赖朝向。
- 安全区：细条底部锚 safeArea −10pt，命中带下扩 14pt 仍在安全区上沿内，无遮挡系统件。
- 手势冲突：B 的 4s 长按、C① 的单击/双击/0.55s 长按切主题同挂台身空白域，域重叠已在组件注释中自认（MiniBarPetStage.swift 组件头注）——整删 B 后该重叠面少一层。
- 深色/字号：不涉及。

## 汇总定级表
| 条 | 结论 | 定级 |
|---|---|---|
| A 飞整卡不飞封面 | HeroFlight67 快照对象=整卡 cell，fly() 只改 frame | 已定级 |
| A 回程卡一下 | finish() 硬换 + 身份分支布局瞬时落定；单帧 82.78 实证 | 已定级（分支归属候选待日志） |
| B 白环还在 | StageCycleProgressRingView，仅剩宠物 4s 开启手势一处在用，三宿主接线 | 已定级 |
| C① 细条点不动 | 同步态路径成立（V3 实证可通）；疑形态/识别器失同步（(63) 前科） | 候选待日志（minibar.form 一行判读） |
| C② 详情页拖动闪帧 | 舞台 progressDriver 接线缺 miniSeekDragging 同款守卫，双写打架 | 已定级 |
