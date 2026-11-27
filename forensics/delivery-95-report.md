# (95) 交付报告 — 依据 forensics/log-94-verdict.md 定案清单 10 条 ＋ Miller 追加第 11 条

- 分支：release-95（自 release-94 开，94 的判读提交 1c5376cd 已先行 push）
- 提交：`baf93b90`（第 1–10 条）＋ `f4b16dfa`（第 11 条）
- CI：run **45939029164**（含全部 11 条）**success**；此前 10 条版 run 45937694528 亦 success
- IPA：`~/workspace/folia-deploy/build95/Folia-unsigned.ipa`，**49,207,493 字节**
- 包核验（已实测）：CFBundleVersion=95 ✓；入场母带 entry-v5-faststart.mp4 md5 `8aed0fb4a5e9a0f500184f8a7dae45a9` ✓；包内 WebEffect 束含 `/api/netease`、`/api/qq`、`/api/kugou` 三项 API base 与 `songPreviewPlaying` ✓；主二进制内 p95 系列字面量在位（`p95 deck capsule h` ×3 三宿主、`p95 fx clear fx` ×4 四特效、dismiss try ×2、probe/pop seg/wall bypass/seam qr/deck guard 均在；个别短串如 `p95 rec geo` 系 Swift 小字符串内联、strings 不可见，同块旁证在位，非缺失）
- 表述三档：以下每条只记「代码已改＋CI 编译已过」；「日志已证」仅指 (94) 判读已实证的断点机制；**全部 11 条均未真机验**，真机结论等 Miller 装包后按文末清单对面包屑判定。

## 第 1 条 点按黑洞（四特效逐个覆盖）
- 代码已改：tapProbe92 增识别器级原始落痕（`p95 probe raw should/fired`、`p95 probe first` 强在岗、`p95 probe arm` 附同窗共存识别器清单）；结构兜底看门狗 probeGuardCheck95——任一特效开启期，点按命中 ConsolePanel82 登记的特效钮帧/dim 帧（fxFrames95/dimFrame95）后 350ms 内无 handler 落痕（handlerTrace95 计数判据），probe 直接关特效（src=probe95）或发 `.foliaConsoleDismiss95` 通知请控制台 dismiss（reason=probe95）。烟花/孔明灯/雪/风四钮帧逐个登记、逐个可达，不再依赖单一路径。
- 断点机制日志已证（(94) 判读：风的关指令从未到达 handler）；吞点按的具体层仍未定性，本条以「原始落痕＋看门狗兜底」双路处理，真机复现时先看 `p95 probe raw` 有无落痕分流定性。

## 第 2 条 控制台 dismiss 关闭尝试面包屑（四特效逐个列）
- 代码已改：dim 两路在进入 dismissConsole93 前落 `p95 dismiss try src=dimroot/dimgesture`（不只记成功路径）。
- 四特效关闭链逐个自证（set 函数 1→0 收尾各落 `p95 fx clear fx=<代号> src=..`）：
  - 烟花 fw：GlobalFx87.swift:987
  - 孔明灯 ln：GlobalFx87.swift:1001
  - 雪 sn：GlobalFx87.swift:1014
  - 风 wd：GlobalFx87.swift:1027
- 真机判定：任一特效开启期点外关台，应依次见 dismiss try → 对应 fx clear → 控制台收起，缺一环即该环断。

## 第 3 条 推荐卡触发统一
- 代码已改：触发从烟花时间轴 t>12.6s 摘除，改任一特效开启边沿统一调 maybeShowRec95（与 p94 fx arm 同点）；全关复位 recShown；provider/rec 为 nil 落 `fx87 rec miss why=noprovider/norec`；呈现落 `p95 rec geo`，与控制台 presentedCardFrame 同宽对账。
- 断点日志已证（(94) 判读：showRecCard 唯一调用点在烟花时间轴）。

## 第 4 条 弹台 inter 分段仪器
- 代码已改：`p95 pop seg` 取代 p94 版，分段新增 print 段（拍立得打印打点）与 rest 归属字段，inter 全程可归属；目标 tap→first ≤ 转场＋50ms 不变。本条只补仪器不定修法——真机取一段 `p95 pop seg` 后按 rest/print 归属再定修点。

## 第 5 条 版式切换归一
- 代码已改：歌单页 appear 旁路 refreshPlaylistLayoutFromDefaults92 改走 switchPlaylistLayout93 同一实现（src95="appear"，p94 wall sw 全套行加 `src=seam|appear`）；applyPlaylistLayout91 改为先装载＋可见性验证才互换 isHidden，落 `p95 wall bypass mode=.. vis=..`。黑底列表直显前有可见性验证兜底。

## 第 6 条 歌单缝（Miller 已批加宽）
- 代码已改：缝宽 64→**120**（seamPlan85 openWidth＋重开/展开收起/contentOpacity 三处同宿主同步）；A/B 内容避缝起点同步 64→120（杂志头 x 与宽、唱片架头 leading、shelfCV sectionInset、杂志 cell 编号 x=120/封面 x=156/textX=212）；胶囊钮 cornerRadius 改布局时取 `min(w,h)/2`（废写死 15）；缝底播放区 span95=min(120, contentW−8)，三钮全在界内；歌单名 pill 加 adjustsFontSizeToFitWidth、minimumScaleFactor 0.66（长名缩字显示，不再只剩一个点）。(b)(c)(d) 在 SeamMaster 共用母版，主页缝同源生效属预期（缝全页统一口径）。

## 第 7 条 舞台旋转第五门
- 代码已改：p94RotMaybeRelease 加条件 stageRotLaidSize86==targetSize，不符先清 pending、无条件补一轮 layoutStage＋pushSnapshot、更新 laid 后递归重走全部门；`p94 rot ready` 加 `laid=/target=` 字段自证。3 秒 tmo94 兜底行未动——**去留仍待 Miller 定**（本报告再次明示）。

## 第 8 条 deck cov 探针守卫自证
- 代码已改：probeDeckRender94 守卫未命中时每会话每组合只落一次 `p95 deck guard pres/coll ev
...[truncated 4584 chars]