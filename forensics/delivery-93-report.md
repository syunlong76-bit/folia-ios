# (93) 交付报告

- 施工依据：Miller 2026-11-27 09:51 拍板「圣诞歌词特效可以，包括前面的问题处理了一起发我下一包」；A 组依据 forensics/log-92-verdict.md；C 组依据样片 Space ge-dan-qiang-pai-ban-zhong-she-ji-yang-pian 定版；D 组依据样片 sheng-dan-ge-ci-te-xiao-yang-pian v2 视频（Miller 已验通过）。
- 分支/提交：release-93，代码提交 c7aef577＋CI 修复 f54c88d1（physFootprintMB 归属修正，见未决项）。
- CI：首跑 45926064363 failure（单个符号归属错误）→ 修复后 45926510250 **success**。
- IPA：Folia-unsigned.ipa **49,130,405 字节**，存 ~/workspace/folia-deploy/build93/。
- 包内核验：CFBundleVersion=**93** ✓；入场母带 entry-v5-faststart.mp4 md5=**8aed0fb4a5e9a0f500184f8a7dae45a9** ✓；新符号结构旁证齐（ChristmasTreeStageRenderer、presentedCardFrame、shuffleGlyph93、dismissConsole93、SeamGlyph93、glyphCoverage93、switchPlaylistLayout93、ConsoleDimRoot93、fxSparkSprite93 均在二进制中）；包内 WebEffect 束含 /api/netease、/api/qq、/api/kugou 三项与 songPreviewPlaying/songPreviewLoading 两键 ✓。
- **文叔叔上传未由本施工线执行**：游客上传需浏览器操作，本线无 live browser 权限；IPA 已备好在 build93/，请主聊天经浏览器上传文叔叔后交付 Miller（约 24h 销毁、传完立刻发并提醒马上取），muse.ai 链接作备用。

## A 组（(92) 日志定案修复）

- **A1 控制台点外不消失**：定位到旧判定用 `card85.frame.contains`（transform 后的包围盒）在弹性形变期可把卡外点误判为卡内。修法三层：①控制台根视图换 ConsoleDimRoot93，hitTest 对卡外点直接返回根视图自身、点按在 touchesEnded 第二路送达（不依赖手势识别器）；②卡内外判定改 convert＋bounds；③全部关闭入口（dim/下滑/动作钮/宿主消失）统一走 dismissConsole93(reason:)，面包屑 `p93 dismiss r=dim|action|hostgone`。另 SceneDelegate 在播路由：top 为 ConsolePanel82 时先无动画 dismiss 再同代际续跑路由（`p93 route thru gen=`），(92) 的 unstable-modal-presented attempts=6 giveup 成因消除。诚实注记：控制台本无独立关闭按钮（(85) 起即无），关闭路径为点外＋下滑，未新造按钮。
- **A2 风 5 秒自关**：元凶实锤——GlobalFx87 stepWind 内硬编码 `nowMs - wdStart > 5000 → stopWind()`，已删除；生成概率与雪/烟花/灯逻辑未动。非手动关风落 `p93 fxauto fx=wd src=` 以便下份日志区分。雪 +12s 自融按定案未动。
- **A3 控制台弹出 606ms 帧间隔**：拍立得打印移出 present 关键路径（入场弹簧 completion 后才启动），Polaroid90 打印改分帧推进（每渲染周期至多推进 2 张、绝对时刻对齐旧 stagger、视觉时序不变）；present 起点注入时间戳，下一次主线程间隔落 `p93 pop gap=<ms>ms` 自证，目标 <50ms 待真机日志对账。
- **A4 内存 515MB → ≤450MB**：构成账见专节。
- **A5 探针补强**：`p93 probe arm fx=<开启集>`/`p93 probe off`（特效开启集边沿自证，区分探针没在岗）；`p93 tap own=card|host|none zone=<九宫格>`（覆层 hit-test 归属，与 p92 tap ok 共用每秒 ≤2 条节流）；dismiss reason、route thru、pop gap、mem、fw dt 均为本包新增自证行。

## A4 内存构成账（基线为 (92) 日志实测、改后为结构估算，未真机实测）

| 项 | (92) 实测/现状 | (93) 改动 | 估算影响 |
|---|---|---|---|
| 全应用峰值 | 515MB（越 450MB 硬线） | — | 目标 ≤450MB，待真机 footprint 对账 |
| 墙封面缓存 LRU | 上限 160MB | 改 128MB（仍在 120–180MB 口径内），`p93 wallcache mb=128` | 峰值上限 −32MB |
| 雪粒子 | 每粒独立 CALayer＋阴影路径（雪窗 +45MB 主因之一） | 全场共享一张 36×36 精灵（约 5KB 全程复用） | 雪窗增量预计降至个位数 MB |
| 联动雪檐/雪堆 | 无上限、离窗砖也建檐 | 雪檐 ≤120、雪堆 ≤24、不在窗的砖不建檐 | 封顶小量常驻 |
| 四特效启停 | 无内存对账行 | 各落 `p93 mem fx=<fx> on=0|1 mb=<MB>` | 下份日志可逐项对账 |

未实测声明：本线无真机，改后峰值未实测；是否回到 ≤450MB 以 Miller 真机日志的 footprintMB 尾巴与 p93 mem 行为准。

## B 组（真机图点名）

- **B1 播放台减一号**：展开台高 124→112、控制行 48→43、字形 17/16→15/14、钮内距 5→4；三宿主（主页墙/歌单墙/舞台）封面与中央/控制台钮径 42→38、行位按 112 台高重排（顶留 9、行间隔 6–7，改前顶留 5、钮→轨间隔约 1）；收起态细条与 5 秒收起零触碰。面包屑 `p93 deck size=112/43`、`p93 deck host=home|wall|stage`。
- **中央钮空灰圆无字形**：字形工厂侧加实测自证——DeckGlyph82 渲染后量 alpha 覆盖率，play 覆盖率 <2% 当场改填充三角重渲兜底，面包屑 `p93 deck glyph=play cov=<‰> fb=<0|1>`。丢失环（工厂描边/宿主渲染/着色）由下轮日志裁决：fb=1 即工厂侧丢失已被兜底接住；cov 正常仍空则在宿主侧。
- **B2 shuffle 统一**：SF "shuffle" 删除，改手绘 shuffleGlyph93（量得同行 .list 线宽 1.4 后对齐之，非估值）；控制台与舞台三处消费点零改动自动受益。repeat 族仍 SF 符号，未动。

## C 组（样片定版移植）

- **C1 缝底图标排**：新增本地字形工厂 SeamGlyph93（24 画布、线宽 1.7、圆头、默认 16px，按样片 SVG 逐个换算）；设置＝8 齿标准齿轮（非 SF）；控制台入口＝双音符上下对称字形。主页缝工具排 4→5 枚（新增控制台钮，新闭包接线、既有四钮回调零改动）；歌单页展开档新增同排式控制台钮。**存疑**：歌单页书脊档（64 宽）空间不足未装控制台钮，该档仍走点播台既有控制台钮。
- **C2 书库缝四入口图标化**：爱心/云/书本/服务器同套细线图标；爱心、云、Navidrome 走既有落点，书本新接 DiaryViewController90（与控制台日记本钮同页）；点按落 `p93 seam ent=`。**窄档差异**：64 缝宽下一行四枚命中格仅 16pt，窄档折 2×2 保 30pt 命中，宽档一行四枚与样片一致——请真机验收时留意此适配判断。
- **C3 排版三段胶囊双页同步**：两页胶囊字形统一 SeamGlyph93（16px、砖墙格 ×0.86）；歌单页缝新增同款胶囊（新闭包 onLayoutMode93）；单一状态＝同一 UserDefaults 键双向回刷（主页 viewWillAppear 补重读——此前缺失，是双页不同步的根因之一）；切换改交叉淡化（新视图原地备数据出首帧、旧视图承托、0.25s 双向 alpha 后才隐藏、不动 z 序、不整墙 reloadData），落 `p92 plist mode=`＋`p93 layout sw=`。
- **C4 控制台特效钮与推荐卡**：四特效钮核对已与点播台 A4 字形同源（DeckGlyph82 fx* 工厂），未改；**控制台宽幅已按样片改**：min(620px, 屏宽−20px) 换算原生 min(620, bounds.width−20)——竖屏卡宽由约 296 变约 370，各行观感需真机看。推荐卡改消费控制台 presentedCardFrame（同宽、leading 对齐、卡下方 8pt）；入场按最近开启特效区分（烟花 0.7 缩放绽开/灯下方 26pt 升起/雪上方 14pt 落定带回弹/风侧方 30pt 掠入）；新增 12 秒自动轮换（卡可见且任一特效开时）。

## D 组 圣诞树歌词样式（样片已过、待真机验）

- 新增 ChristmasTreeStageRenderer（原生、走现有样式通路注册）：id=christmas、显示名「圣诞树」、order 180、池面板图标 "tree"、**三击洗牌袋自动纳入（全集 21→22 只）**。
- 粒子总量 7100，与样片逐项对齐：树体 3000＋金链螺旋 340＋歌词 3000＋环境雪 650 远/110 近；采样 1200×300 步长 2、字宽 min(7.4, 可见宽×0.97)、镜头 40 秒一圈；时序：汇聚恒 1.0s、碎散恒 0.8s、停留＝行长−0.8s（5 秒行恰停留至 4.2s，与样片 v2 的 1.0/4.2/0.8 口径一致）。
- 性能口径：粒子走烘焙精灵贴图绘制，无 CPU 全屏光栅；帧率自证 `p93 xmas fps=`（每 2 秒采样）待真机对账——每帧约万次贴图绘制，60fps 是否成立以真机面包屑为准，本线未实测不宣称达标。地面暖光池/金星光晕/远景锥/雪金混色为视觉近似（样片为滤色发光、原生为普通透明度），真机观感可能略淡。

## E 组 烟花流畅度

- 星粒改按花色烘焙精灵图集（fxSparkSprite93，缓存上限 64）＋加色混合贴图绘制，前帧残影以 alpha×0.35 贴图近似（原 hist 拖尾退役）；工坊定版参数（大小×0.85/密度×1.1/辉光×1.7/金）未动。新增 `p93 fw dt=<ms> n=<粒子数>`（每约 2 秒一条），下份日志可判烟花帧况。(92) 日志无烟花时段数据，本项为结构修、效果待真机＋日志双验。

## 顺手项

- folia-major 四语言包 songPreviewPlaying/songPreviewLoading 已补齐并随 WebEffect 换束入包（包内已验）；前端构建三项 VITE base 齐备、chunk 已验。

## iOS 适配自查

- **横竖屏**：控制台新宽幅横竖统一公式（min(620, 宽−20)），竖屏变宽为已知取舍、待真机看排版；圣诞样式按短边适配、横竖屏均成立（树高取 min(高×0.62, 宽×1.05)）；缝窄档工具区因五钮增高（0.135H），小屏/横屏带高不足时胶囊按既有规则隐藏、版式可经宽档或歌单页切。
- **安全区/灵动岛**：本包未改任何宿主安全区逻辑；推荐卡落位加贴底收口（maxY 不出窗）；控制台卡新宽幅不触安全区边缘（左右各留 10pt）。
- **系统手势**：控制台根视图 hitTest 只接管卡外点、不拦截卡内与系统手势；无新增与边缘返回/下拉关闭冲突的手势；舞台三击/长按通路未动。
- **深色外观**：新字形（SeamGlyph93/DeckGlyph93）走模板着色、跟随各宿主既有深浅色口径；圣诞样式本身为暗场设计（与网页样片同口径）；毛玻璃面沿用系统材质未改。
- **字号下限**：本包未改任何文字字号；图标尺寸 15–17.5px 为样片定版区间；窄档四入口命中格 ≥30pt（2×2 折行保命中）。
- **目标机型**：按 iPhone 14 Pro 基准核对约束数值；圣诞粒子量与烟花精灵化均按帧率自证面包屑留了真机对账口。

## 真机验证清单（每条对面包屑）

1. 控制台开特效后点卡外 → 控制台消失、特效留墙；日志见 `p93 dismiss r=dim`＋`p93 tap own=host`＋`p93 probe arm`。
2. 风开启后放 1 分钟不自关；若关，日志 `p93 fxauto` 会写明来源。
3. 控制台弹出帧间隔：`p93 pop gap=` 应 <50ms。
4. 内存：开雪/四特效轮测，看日志尾巴 footprintMB 与 `p93 mem` 行是否 ≤450MB。
5. 中央播放钮字形在否；`p93 deck glyph=play cov= fb=` 裁决丢失环。
6. 圣诞树样式：选样式或三击抽到，`p93 xmas fps=` 看帧率；歌词聚字时序对样片 v2。
7. 烟花开 30 秒：`p93 fw dt= n=` 看帧间隔与粒子量。
8. 双页排版胶囊互切：主页切了歌单页跟随、反之亦然；切换无黑闪；`p93 layout sw=`。
9. 推荐卡：开任一特效后卡在控制台正下方同宽、入场形态随特效、12 秒轮换、点卡切歌。
10. 控制台竖屏新宽幅（约 370）各行观感；歌单页书脊档无控制台钮是否可接受；书库缝窄档 2×2 是否可接受。

## 未决项

- 文叔叔上传待主聊天浏览器执行（见文首）。
- CI 首跑失败已定案修复：Fx 组 memLog93 误写 StageStyleStore.physFootprintMB（实在 StyleOpenTrace），f54c88d1 改对后 CI success；属本线静态核查漏网（无本地 Swift 编译面），已认。
- 烟花专项日志仍缺（(92) 时段被环形缓冲滚掉）；本包 dt 面包屑已备，仍建议 Miller 开烟花 30 秒后立刻导出一份日志。
- 圣诞帧率、A3 帧间隔、A4 峰值均为「已落自证面包屑、待真机日志对账」，未实测不宣称达标。
- 歌单页书脊档控制台入口、C2 窄档 2×2、控制台竖屏宽幅三处为施工适配判断，待 Miller 真机拍板。
