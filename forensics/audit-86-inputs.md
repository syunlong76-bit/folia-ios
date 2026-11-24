# (86) 审计报告：(85) 真机未过四条定位

- 审计对象：release-85（提交 e9101085）；网页版源码 folia-major PonderBravais 系。
- 量测图：本轮 Miller 5 图。注意文件与口头编号的对应：横屏图是 `78685D8F…jpg`（1179×543，系 2556×1179 的等比缩放，1pt = 1.384 文件 px）；任务书点名的 `4BF86106…jpg` 实为竖屏歌单墙图（1179×2556），其底部系统线量得 420px = 140pt、高 15px = 5pt、底距 24px = 8pt，与 (83) 量测一致。

---

## 审计一：歌单页点头像仍不能定位

**结论：歌单页上唯一能点的头像被工具条的「展开门」挡在门后——绑定本身在，但头像只在工具条展开后的 3.5 秒窗口内可点，闲置自动收回后点头像位置毫无反应；且歌单页没有主页那样的缝内常驻头像可作第二入口。**

歌单页（WallPrototypeViewController）上的头像共 2 处：

| # | 位置 | 绑定 | 出处 |
|---|------|------|------|
| 1 | 顶部工具条头像（SeamToolbarView.avatarButton，32×32，leading+6） | `locateCurrentTrack(via: "avatar")`（本墙内定位） | WallPrototype:2667-2670 装配；SeamToolbarView:99/257/810 |
| 2 | 点播台封面（miniCover，非头像、是封面区） | `locateCurrentTrack()`（via=cover） | WallPrototype:1350 |

缝内（PlaylistSeam85View）**没有头像位**（构成只有返回/折叠/竖排名/计数/播放/展开，Seam85Views.swift:368 起），与主页缝不同——主页有缝头像（HomeSeam85View.avatarButton → avatarLocate85，HomeWall:3939）常驻可点，歌单页没有这个第二入口。

为什么工具条头像吃了绑定却点不动——SeamToolbarView 的双态门：

- 收起态 `hitTest` 只返回 grabberHitView（SeamToolbarView:547-556），其余点按全部穿透到墙面；
- 收起态内容组（含头像）`alpha=0` 且 `isUserInteractionEnabled=false`（applyToolbarState，SeamToolbarView:612-676）；
- 展开后 **3.5 秒**闲置自动收回（scheduleIdleCollapse，SeamToolbarView:603-610）。

即：用户必须先点左上角小横线展开工具条、在 3.5 秒内再点头像，定位才可能触发。Miller 在歌单页点头像时工具条绝大多数时刻是收起态，点按穿透到墙面、无任何反馈——与「点了没反应」完全吻合。(85) 报告只核了绑定落点，没有核这道门。

第二断点（绑定真触发时）：`locateCurrentTrack` 在 WallPrototype:2199-2205——在播曲不在本墙 `entries` 内（从别的歌单/主页起播后进本页点头像）时落 `locate85 result=miss` 并 `openNativeStageFromWall()` 改开舞台页，不滚动定位。用户感知同样是「没定位到正在播放的歌」。

**修法**：
1. 歌单页缝内补常驻头像位（与主页缝同位：工具格上方），绑本墙 `locateCurrentTrack(via: "avatar")`；或把工具条头像移出双态门（收起态保留头像常驻可点）。二选一，前者与网页缝构成更一致。
2. miss 分支按主页口径改：只 toast＋`locate85 result=miss`，不许改开舞台冒充定位（与 (85) 对主页死点一的处理对齐）。

判读见证（下轮日志）：点头像应出现 `sidebar85 tap dest=avatar`（缝头像）或 `locate85 via=avatar host=wall`；若只有穿透无此行，即门未开。

---

## 审计二：横屏小白条仍不等长

**结论：218 这个常数本身没错，但它只写在 `setMiniBarForm` 的尾巴上——三宿主的旋转回调没有一处重设轨宽。条在竖屏收起（常数被写成 140）后转横屏，轨宽永远停在 140，与系统横线 218 差 78pt。这就是改了多版不治的实根：每版都在改常数，没人改写入时机。**

运行期轨宽的决定链（收起态）：

- 唯一写入点：各宿主 `setMiniBarForm(collapsed:)` 尾部 `miniTrackWidthC?.constant = DeckLayout84.collapsedTrackWidth(portrait: view.bounds.width <= view.bounds.height)`——HomeWall:2706、WallPrototype:1827、Stage:3864（stageTrackWidthC）。公式本体 Deck82.swift:166-170（DeckLayout84，竖 140／横 218）。
- 装配初值恒 140：HomeWall:1727、WallPrototype:906、Stage:3185。
- `setMiniBarForm` 只在形态切换（收起/展开）、宿主认领对齐（viewWillAppear 的 resyncMiniBarFormToGeometry70，且仅当几何形态与旗标不一致时）时被调用；**旋转不调用它**：
  - HomeWall viewWillTransition（HomeWall:751 起）completion 只重断言台身宽 `miniBarWidthConstraint = min(w,h)−24`，不碰 miniTrackWidthC；
  - WallPrototype viewWillTransition（WallPrototype:2460 起）与 Stage viewWillTransition（Stage:856 起）完全不碰点播台轨宽（Stage 全文 stageTrackWidthC 仅装配/形态两处引用）。

量测（本轮横屏图 78685D8F，1179×543，1pt=1.384 文件 px）：底部两条叠线——上条（我方轨，带花朵把手）右端 x≈688 文件 px，由居中对称推左端 ≈491，宽 ≈197 文件 px ≈ **142pt**；下条（系统线，灰）右端 ≈745 文件 px，宽 ≈311 文件 px ≈ **218-225pt**。差 ≈ **76-83pt**，与「140 vs 218」的代码推演（差 78）逐项吻合。我方轨高两条同为约 5pt、纵向锚位无误（轨在系统线上方相接），只差宽度。

**改哪一行**：三宿主 viewWillTransition 的 completion（与台身宽重断言同一收尾点）各补一行——收起态时按新 size 重写轨宽：
`miniTrackWidthC?.constant = DeckLayout84.collapsedTrackWidth(portrait: size.width < size.height)`（Stage 用 stageTrackWidthC）。或更省事：把该赋值从 setMiniBarForm 尾部抽成 `refreshCollapsedTrackWidth85()`，形态切换与旋转收尾共用。DeckLayout84 常数（140/218）不要再动。

---

## 审计三：缝的排版对照网页

**结论：原生缝是「按网页构成清单、用绝对 pt 值另排了一套」，网页的相对比例排版与选中态配色没有搬过来——具体走样 7 处；头像只显示「大」字是因为缝头像没走全仓统一的封面加载链，自己裸连 URLSession 直下且失败静默。缝背景现行是纯黑 0.34 平涂，网页是 0.8 深色纸面＋投影。**

网页参数出处：ponderBravaisSeamGeometry.ts（BRAVAIS_HOME_SEAM_GEOMETRY / BRAVAIS_SPINE_GEOMETRY / homeDock）、PonderBravaisWallParts.tsx（BravaisHomeSeam 渲染）、PonderBravaisHomeSeamSurface.tsx:51。原生出处：Seam85Views.swift（HomeSeam85View.build/layoutSubviews、PlaylistSeam85View）、宿主装配 HomeWall:3924 / WallPrototype:1868。

### 主页缝逐项对比

| 项 | 网页 | 原生 (85) | 走样 |
|----|------|-----------|------|
| 缝纸背景 | 实色纸或透光档 rgba(22,22,27,**0.8**)，带 0 0 18px 黑投影（WallParts seamFrame） | 黑 **0.34** 平涂＋两侧 0.5pt 白 0.12 发丝线，无投影（Seam85Views:131） | 透明得多、墙面透出，网页是近不透明的深色纸 |
| 标题「书库」 | top 2.8%、white/**85**、extrabold、字距 0.3em | contentTopInset 起 y=0、11pt semibold、white/**0.5**（Seam85Views:126-130） | 色浅一级、字重轻一级、无字距 |
| 折叠钮 | 裸 chevron 图标，top 8.5%、高 2.4%、white/55，**无底衬** | 28×28 圆角 14 的**芯片**（白 0.10 底）、y=22 固定（Seam85Views layout） | 多了芯片底 |
| 页签几何 | 相对缝高：top 0.118 起、**步距 0.07**、高 0.062；宽 = 缝宽 0.40 居中 | 固定 pt：y=58 起、**步距 60**、高 54；宽 = 64−20 = **44（缝宽 0.69）** | 步距/高度未按比例（网页按 545pt 缝高折算步距 ≈38pt、高 ≈34pt），原生签块又高又宽、间距散 |
| 页签选中态 | **白 0.9 圆角全圆（pill）＋深色字**；未选透明底＋white/62 字、7px bold 字距 0.18em | 选中 = 白 **0.13** 底＋白字、圆角 10 的方块；未选白 0.5 字、13pt medium 无字距（refreshTabSelection） | **配色整个反了**：网页选中是亮白 pill 深字，原生是暗灰块白字——图一里「歌单」块发灰、网页图四里是亮白，这是「只学皮毛」最显眼的一处 |
| 中段直达 | 两列并排竖排小字（我喜欢的音乐／云盘），top 64%、white/55、无分隔线 | 单列「我喜欢的音乐」在剩余空间**纵向居中**、11pt white/70、上方加 20pt 分隔线；**无云盘** | 列数、位置、条目都不同 |
| 账户位 | 几何 top 78.2%、高 7.2%（homeDock account）；渲染为圆，宽 26% 缝宽、白 0.25 描边（WallParts） | 32×32 圆，贴工具格上方 42pt（toolsTop−42） | 位置锚法不同（原生随工具格、网页按 78% 比例），尺寸接近 |
| 工具格 | 底部 2.5%、高 8%、左右 inset 16%、**裸图标** 9px white/70、无底衬 | 底部两行两列 28×28 **芯片**（白 0.10 底、圆角 8）、tint white/88 | 多了芯片底、图标大一圈 |

### 歌单缝（书脊）逐项对比

网页 BRAVAIS_SPINE_GEOMETRY（相对缝高）：back top 0.024、fold 0.088、title top 0.16 高 0.38、count top 0.56 高 0.06、play top 0.84、expand 0.905；back/fold/play/expand 宽 = 缝宽 0.6。
原生 PlaylistSeam85View.layoutSubviews：back y=0、fold y=34（均 28×28）；title y=74、高 = contentH−218（**弹性拉满剩余空间**）；count 紧随 title+6、高 44；play 36×36 在 contentH−82、expand 28×28 在 contentH−34。
走样：①标题块高度——网页是定比 0.38、计数钉在 0.56；原生把标题拉满、计数随标题底走，长歌单名时计数位置漂移；②back/fold 步距：网页 (0.088−0.024)=0.064 缝高，原生固定 34pt；③play 钮：网页 0.6×64≈38 方形裸钮，原生 36 圆角 18 带白 0.16 底（近似，但多了底衬）。

### 头像为什么是占位「大」字

- 回填通路本身在：HomeWall.seamRefreshAccount（HomeWall:4203-4257）同步缓存＋fetchLoginStatus 两路都调 `homeSeam85?.setAccount85(nickname:loggedIn:avatarURLString:)`，与工具条头像同源同值。图一工具条头像显示真图、缝头像显示「大」，说明 URL 有、断在缝自己的加载段。
- 断点：HomeSeam85View.setAccount85（Seam85Views.swift，setAccount85 函数）用**裸 `URLSession.shared.dataTask` 直下原始 URL**，闭包只 `guard let data`——无错误处理、无状态码校验、无缓存；且每次调用先把 `avatarImageView.image = nil` 并 cancel 上一任务。而工具条头像走 WorkbenchCover.loadAvatar（WorkbenchCommon.swift:48），经 **NativeCoverLoader 的 proxiedURLString 代理链**（本地服务代理＋缓存＋失败回退直下）。网易云头像 URL 为 http 明文域（p1.music.126.net 系），裸直下会被 ATS 拦、data 为 nil → 静默失败 → 永远停在昵称首字占位。
- **修法**：缝头像改走 WorkbenchCover.loadAvatar（与工具条同一条链），删掉自带 dataTask；setAccount85 的 avatarTask 字段一并退役。

### 缝背景改油画＋长按循环 4 套的施工依据

- 点播台现行主题底图（MiniPlayerThemeLayer.swift:310-322）：Bundle 子目录 `Resources/ThemeArt/` 下 4 张 JPG——花海 monet-meadow.jpg、雪景 monet-snow.jpg、星空 star-ref.jpg、海洋 ukiyo-ocean.jpg；`MiniPlayerTheme` 枚举 none/meadow/snow/star/ocean（MiniPlayerThemeLayer.swift:9-10），`themeImage(named:ext:)` 为 internal static 可直接复用，`backgroundImage(for:)` 为 private 需放开或照抄映射。
- 主题状态单源：`MiniPlayerTheme.stored`（点播台长按 0.55s 循环 `.next` 并写 stored＋发 `.foliaMiniPlayerThemeChanged` 通知，HomeWall:2072-2093）。缝背景跟同一 stored 值、订阅同一通知即可与点播台恒同图；缝上长按手势照抄点播台口径（0.55s、写 stored、发通知），两处长按天然互通循环。
- 缝现行背景落点：HomeSeam85View.build / PlaylistSeam85View.build 的 `backgroundColor = black 0.34`（Seam85Views:131、:385）——改为 UIImageView（scaleAspectFill＋clipsToBounds）垫底＋保留一层暗罩（点播台同款 scrim 黑 0.18，MiniPlayerThemeLayer.swift:104）即可；主题为 none 时回落现行黑 0.34。

---

## 审计四：小白线残留＋双时间约束

### 小白线

**结论：残留的白线就是顶部工具条（SeamToolbarView）收起态的 grabber 横线——(85) 撤掉的是速记簿缝合把手，这条是另一个元素，从没被撤过。图五量测与代码参数逐项吻合。**

- 本体：SeamToolbarView.grabberView（SeamToolbarView.swift:334-377）：**36×4pt、白 0.85、圆角 2、leading+12、纵向居工具条带 centerY**；配套隐形命中垫 grabberHitView 76×28（leading+2）。
- 图五量测（55D6BE35，1179×2556，÷3 换算）：左缘上方灰白短线 x≈38..148px = **13..49pt**、y≈246..255px = **82..85pt**、长 ≈36pt、高 ≈3.5pt、灰度值 78（系控制台压暗层 0.45 黑罩压暗后的白 0.85）。歌单页工具条带竖屏高 165、centerY≈82.5 → 线身 y 80.5..84.5，与量测逐项对上。图四（横屏）左缘同位一线为同一 grabber（横屏带高 44、top=safeArea.top+56，纵位随之不同）。
- 它是三宿主共用的同一元素（主页/歌单/舞台工具条都是 SeamToolbarView），所以主页图一左上也有——Miller (84) 说的「取消左上角小白线」指的就是它；(85) 只处理了 SketchbookDrawer 的 edgeHandleSuppressed84（HomeWall:483），没动到它。
- **撤除点**：SeamToolbarView.swift build() 的 grabber 装配段（:334-377）——grabberView 与 grabberHitView 一并摘除/恒隐藏；连带 hitTest 收起态分支（:547-556）与 applyToolbarState 中 grabberView.alpha 行（:639）需一并处理。注意后果：grabber 是工具条收起态的唯一展开入口，撤线必须同时给工具条换展开方式（缝头像常驻化后，工具条展开入口可改由缝/头像区承担——施工时定，不要只删线留死条）。

### 双时间标签现行约束（(85) 后）

三宿主已同构（(85) 第六条统一后）：

| 宿主 | 左时间 | 右时间 | 出处 |
|------|--------|--------|------|
| 主页墙 | bar.leading **+16**，宽 40 | bar.trailing **−16**，宽 40 | HomeWall:1786-1794 |
| 歌单墙 | bar.leading **+16**，宽 40 | bar.trailing **−16**，宽 40 | WallPrototype:962-967 |
| 舞台 | bar.leading **+16**，宽 40 | bar.trailing **−16**，宽 40 | Stage:3226-3236 |

台身本身距屏边：台宽 = min(屏宽,屏高)−24 居中（竖屏 393 → 台宽 369、左右各 12pt 屏距），故时间标签距**屏幕**边 = 12+16 = 28pt；但距**台框**只有 16pt，且台圆角 35（全胶囊，DeckLayout82.deckCornerRadius），进度行纵位偏离台中心约 14-20pt，该高度处胶囊弧线内收约 3-6pt，标签到可见弧边的实际净距只剩 ≈10-13pt——即 Miller 说的「卡在边缘」。
**施工数值**：三宿主同改 16 → **28**（距台框 28、距屏边 40），轨两端约束（track lead/trail 锚时间标签 ±8，HomeWall:1721-1722 等）自动跟随、轨相应缩短 24pt，无其他连带。

---

## 汇总：(86) 施工清单（按审计顺序）

1. 歌单缝补常驻头像位绑本墙 locate（via=avatar）；locate miss 分支去舞台冒充，改 toast＋落痕。（审计一）
2. 三宿主 viewWillTransition completion 补轨宽按新朝向重写一行；常数 140/218 不动。（审计二）
3. 缝排版按网页相对比例重排：选中态改白 0.9 pill＋深字、页签步距/宽度按缝高缝宽比例、折叠/工具去芯片底、直达改双列、缝纸改 0.8 深色＋投影；缝头像改走 WorkbenchCover.loadAvatar；缝背景垫 ThemeArt 油画（与点播台同 stored 主题、长按 0.55s 循环 4 套、订阅 .foliaMiniPlayerThemeChanged）。（审计三）
4. 摘除 SeamToolbarView grabber 线身＋命中垫并处理 hitTest/alpha 残引用，同时给工具条定新展开入口；三宿主双时间 16→28。（审计四）
