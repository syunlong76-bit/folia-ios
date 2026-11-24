# (81) 真机会话日志判读（2026-11-24 晚）

日志：`~/workspace/user/files/upload-bf1a117e.txt`，156,509 字节 / 1201 行（与 (79) 日志同体量，滚动留存）。

## 窗口结构（先说清，决定多条结论的等级）

- **尾巴段**（1–201 行）：2026-11-24 11:17 CST 的一段 (81) 运行（footprint≈110MB，paw.face81 在位可证是 (81)），约 20 秒。
- **本会话段**（202–1201 行）：**18:10:40–18:12:55 CST，仅约 2 分 15 秒**，恰是 Miller 18:12 补测（町景/爪印/点头像）那一窗：舞台经墙面双击进入 ×3（全竖屏）、町景在场、歌单墙浏览 18:11:49–59、18:11:58 后台路由切歌（track 3417735195）、18:12:03 导演落判、18:12:51 打开设置。
- **主验收时段（18:09 发结论之前的操作）不在文件内**：快速拖墙、横竖屏旋转、竖屏岛查看都发生在窗口外。两段均无 app 启动点（wit79/wit80/wit81.live 全文 0 次、无 appStart 行），所有「装配即落痕」类见证先天缺席，不作哑火判。
- 全文 `portrait=0` 0 次、`stage.rotate76` 0 次：**留存窗口内没有发生过任何一次旋转**。

结论等级：//。

---

## 未过项逐条

### 1. 快速拖动墙面黑屏 —— 机制定案：无占位＋缓存未命中＋请求在途

本窗歌单墙（wall=tracks）样本（18:11:51–57）：

- `wall.tile78 img=0 phimg=0 blank=8` → 6 秒内衰减为 blank=2、blank=1：砖块在图未就位时**既无封面图也无占位图（phimg=0）**，即纯黑面；同刻 `wall.req79 cfg=8 req=8 nourl=0`——请求已发出、URL 齐全，不是没发起。
- `cvr.stat hit=7 miss=320`（18:11:58）：封面缓存命中率约 2%，绝大多数砖靠现拉现解码，`wall.dec78 wait=8/53ms dec=10/30ms starve=0`——解码排队最长等 53ms。
- 帧：多数窗 p95=16.7ms/hitch=0，但两窗 p99 尖峰 **139.5ms（hitch 3.8%）、209.4ms（hitch 3.4%）**，比 (79) 的最大帧 125.8ms 更大；且本窗 `lattice=0 rebase=0` 全程——**(79) 的 lattice rebase 嫌疑本窗排除**，尖峰与 didScrollMax（≤2.5ms）无关，是帧级渲染/提交停顿。
- 与 Miller 图1 的对应：快滑时新入视砖 = 未命中缓存 + 请求在途 + 无占位 = 黑砖成片，图落地后逐块补上（blank 衰减曲线与此一致）。主页墙快滑本体在窗口外，但机制三环（miss 320:7 / phimg=0 / req 在途）已在本窗实证闭合。

**修法方向**：砖块未就位时先画占位（主题色块/已有低清图），杜绝纯黑面；同时给快滑方向预取与缓存扩容（命中率 2% 是根子）。

### 2. 歌词特效横竖屏切换卡屏 —— 窗口内零旋转，rot81 无从验起

- `webfx.rot81` 全文 0 次；但同窗 `stage.rotate76` 亦 0 次、stage 呈现恒 `portrait=1`——**不是量测哑火，是旋转根本没进窗口**（Miller 的旋转测试在 18:09 主验收时段）。
- 代码附带发现（影响复测口径）：rot81 的 landed 落痕有条件——`webRotCover81!= nil` 才落，且 `beginWebRotCover81` 的快照回调以 `webEmbedStyleId!= nil` 为门。**若复测时用的是原生样式，rot81 永远不会响**，Miller 图6 的样式（童言无忌画面）是否为网页嵌入式未确认；冻结管线对原生样式本就不介入。
- 卡屏本体（冻结盖何时揭、ms 多少）零数据。

**修法方向**：rot81 改无条件落痕（旋转起手/落定各一记，原生样式也记 stage.rotate76 的帧采样）；请 Miller 复测时专测一次网页样式（町景）旋转并立刻导日志，下一窗才能定案。

### 3. 播放台图标点击全无反应＋爪印单击 ❌ —— 接线齐全；点按未交付到按钮本体

- **接线不在嫌疑内**（读码核对）：墙面两宿主（HomeWall / WallPrototype）的 play/prev/next/heart/list 均有 `addTarget(.touchUpInside)`，mode 走 UIMenu，爪印为 `DeckPawButton79` 自带 touchUpInside → `tapped()` 无条件落 `paw.tap81` 并调 `performPawToggle77(actCrumb: "paw.act81")`。浮层爪印同路（src=deck）。
- **日志侧**：`paw.tap81` / `paw.act81` **全文 0 次**（两段皆然）；而点按到达环是活的——本窗 wallproto `minibar.touch75` 多组、`mb.tch78 b` ×7、双击认领 ×3 成功开台、agnostic74 认领 ×3（落 dead75 at=geom）。即：点按进了台身、台身识别器能认领，但**没有任何一次点按落到按钮本体上**（落到爪印必落 tap81，无条件）。断点在「台身到达 → 按钮命中」之间，不在动作接线。
- 具体吞噬者**未确认**：日志不带落点坐标，候选两条——(a) 台身识别器链（单击 require 双击＋长按、delaysTouchesEnded 缺省为真）与 UIControl 追踪竞合，按钮收到的是取消而非 Ended；(b) 按钮实际帧与图标渲染帧错位（点在图标上、命中在别处）。petStage 已排除（hitTest 只认宠物本体、其余透传，读码确认）；seekHit 只占底部 20pt，与主排（中心 −5、40 高）不重叠，亦排除。
- 附带定案（Miller 同条报的「上一曲/下一曲图标反了」）——**真反了**：`DeckIconSet81` 的 prev/next 绘制中，竖条位置是对的（prev 条在左、next 条在右），但**三角尖朝向画反**：prev 的三角尖朝右、next 的三角尖朝左（DeckIconSet81.swift `.prev,.next` 分支，fx 镜像只翻了三角的竖边位置、尖跟着翻错）。四套皮肤共用此绘制，全中。

**修法方向**：三角朝向直接改对（一处绘制）；按钮线补落点坐标见证（touch75 行加 zone/坐标）一轮定案吞噬者，同时给台身单击识别器在按钮区落点让行（delegate shouldReceive 对按钮返回 false）作为相容修法。

### 4. 点头像直达在播歌曲 ❌ —— 新绑定从未被调用；绑定只落在一宿主

- `zone=cover` / `locate81-stage` / `locate81-none` **全文 0 次**；`homewall` 主机名全文 0 次——HomeWall 宿主的台在本文件两窗内从未被点过。
- 代码：`locateCurrentTrackFromCover()` 只存在于 HomeWallViewController，由其台身单击的 zone 分发调用（HomeWallViewController.swift:2027/2073）。**WallPrototype（歌单墙，Miller 补测所在页）的封面区单击没有这个绑定**——其 miniCover 只是 UIImageView，无 zone 分发。Miller 在歌单墙点头像，走的是 wallproto 台身单击链（展开/收起语义），新动作永远不会触发。
- 另注意：即便在主页墙，(81) 改的只是 miss 分支（来源不可知→直达舞台）；来源可知时仍走旧「回来源歌单墙定位卡片」，与 Miller「切换到正在播放的歌曲」的口径仍有一段差，下一包需一并对齐。

**修法方向**：把封面单击绑定下沉到两宿主共用的台分发（一处实现、wallproto 接入），且主页墙主路径也按「切换到正在播放的歌曲」统一，不再分 miss/可知两套语义。

### 5. 中间岛竖屏缺在播封面＋音符 —— 通路能通（本窗 on=1 ×1）；缺失断点

- `isl.cov81 on=1` 本窗 1 次：18:11:58.480，恰在后台路由切歌瞬间（engine load.471 → nowplaying.info.475 → cov81.480），且当时 `nowplaying.info artwork=no source=fallback`、封面.487 才 landed——**簇的点亮与切歌 publish 绑定，点亮瞬间封面图还没到**（先占位后补图，与 (81) 报告的已知边界一致）。
- 但 Miller 主验收看竖屏岛的时段在窗口外，无法证明那时 active 为何为假。代码候选（PetIslandLayer.syncMirrorCenter81）：`liveActivitySuppressed` 时整簇隐藏；签名只由 (active,title) 构成、**页面切换不重发**——若某页进入时 publish 恰逢 suppressed/未 armed，簇会一直缺席到下一次切歌 publish。
- 横竖屏差异无样本（窗口内无横屏岛样本）。

**修法方向**：cov81 签名加 suppressed 与宿主页字段，各页 appear 时强制重发一次中心簇同步；复测时请 Miller 在主页竖屏停留并切一首歌后导日志对位。

### 6. 小白条尺寸仍不对 —— 三宿主 tw=134 在位；差异在「日志量的是轨宽、Miller 量的是整条观感」

- `minibar.form` 本窗：stage 收起 tw=134 ×3、wallproto 收起 tw=134 ×1、展开 tw=329；三宿主代码里收起轨宽约束同为常数 134（HomeWall:1562 / WallPrototype:891 / Stage:2921），日志与代码互证一致——**轨宽本身确实是 134**。
- 但 tw 只是 `progressTrack` 的宽度常数。Miller 图4/图5 量的是整条可见物：收起态台高 h=16（轨高约 4–5pt 嵌在 16pt 细条里）、轨上有 11pt 级花朵把手凸起、轨色为主题色而非白色、且横屏无一条 form 样本可对（本窗 form 全为竖屏场景）。苹果 home indicator 是 134×5 的纯白条、无把手、贴底安全区——**两者在高、构成、贴底位置上都不同源**，轨宽对齐 134 解决不了观感差。
- 横屏 tw：无样本（代码同常数，理应同值，但舞台横屏形态有独立几何，未经日志证实）。

**修法方向**：先与 Miller 对齐口径——他要的是「收起态整条与 home indicator 视觉等同」（134×5、白/同色、贴底、无凸起把手），再按此改收起态 chrome 的高与把手形态；tw 自证补 h 与横竖屏字段。

---

## 通过项见证核对

- **町景手势 ✅**：`webfx.machi81` 全文 6 次，本窗 4 次中 **touch=1 ×3**（18:10:50 / 18:10:55 / 18:11:52，均在舞台进入后），与 Miller 通过互证；首入 touch=0 ×2 是进台装配瞬间，随后转 1。
- **AI 导演 ✅**：本窗 18:12:03 `dir81.local track=65546 mood=love score=9` → `dir81.pick style=lumiere via=local` → `style.mem80 rec … src=dir`，本地判定—选式—入记忆链完整一发。`dir81.keep` 本窗 0 次（窗内无「手动改掉导演选择」事件，非哑火证据）。
- **宠物岛拖动 ✅ / 岛宽**：`isl.geo81` 全文 0 次——其落痕条件是几何签名（总宽|让位）变化才落（PetIslandLayer.swift:981），两窗均不含启动首帧与几何变化点，属窗口外未响，**不是已证实的哑火**；186/204 无日志数字可对，Miller「差不多」与代码常数相容，仅此而已。
- **长按圆点切皮肤 ✅**：本窗无主题切换事件样本（wit 名册外），不另核。
- **详情页宠物带 / 台尺寸统一**（Miller 未测）：`deck.pet81 band=52` 在三次进台各落 1 次、收起转 band=0，`deck.size81` stage 与 wall 同为 w=369——装配与尺寸自证在位，待 Miller 按说明补测观感。

## (80) 预备在本会话的表现

本窗 3 个切歌落定样本（同一 track 3425564193 的三次进台）：

| 时刻 | prep.hit80 | prep.ms80 |
|---|---|---|
| 18:10:41 | hit=1 | ms=1 path=prep |
| 18:10:55 | hit=0 | ms=1 path=repo |
| 18:11:52 | hit=0 | ms=1 path=repo |

读法：首入台吃中预备（hit=1）；后两次是**同一首歌的重复进台**，歌词已在仓库缓存，落 repo 路径 ms=1——不是预备失效，是无预备可吃时的缓存直达。三次歌词就绪耗时均为 1ms 级。尾巴段另 1 样本 hit=0/ms=2/path=repo 同理。`prep.arm80` 本窗 ×2（18:11:58 为 track 65546 武装、style=-，随后导演为其落判 lumiere——预备与导演的接力在本窗可见一例）。**真正的「下一首预备命中率」仍需整段听歌会话样本**，本窗 3 个样本全是同曲重入，不具统计意义，勿据此下结论。

## 附：播放条根链

`mb.claim78` / `mb.disp78` 连续第三窗 0 次；本窗收起态点按样本有 `minibar.claim77 host=stage`＋`via=rescue` 救援一例（18:11:05，舞台收起条点按被取消后救援展开成功，disp77 同刻落）。根链哑火与 (78)(79) 判读一致，仍按红线未动结构，待后续立项。
