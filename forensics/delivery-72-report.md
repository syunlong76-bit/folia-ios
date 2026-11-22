# (72) 交付报告 — release-72

- 分支：release-72（基线 release-71）
- 施工提交：ee377195（18 文件，+850/−114）
- CI：workflow_dispatch build-ipa.yml，run **44988710124**，head_sha ee377195，结论 **success**（一次通过，无编译修复轮）
- IPA：`~/workspace/folia-deploy/Folia-3.7-72-unsigned.ipa`，**47,413,947 字节**（(71) 为 47,391,067，+22,880）
- 上传：**未完成**——remote-storage 上传审批卡超时未获批准（平台对文件上传无持久授权，已知限制），待重新触发审批后补传。

## 验包结果（已过）

- CFBundleVersion = **72**，CFBundleShortVersionString = 3.7 ✓
- 主二进制字符串核查：MiniBarSingleHost ✓、reconcileIsland ✓、prefetchStream ✓、isl.gate / isl.seat.ok / isl.seat.no / isl.drive ✓、wall.rebase.dfr ✓、lattice.state ✓、queue.prefetch ✓
- isl.boot / cvr.stat 字面未在 __cstring 出现：已证为 Swift 小字符串立即数编码——全二进制系统性规律：所有插值字符串首段 ≤15 字节者（含既有已上线面包屑 pet.move asset=、setQueue n= 等）均不以字面存储，≥16 字节者全部命中。两处代码在提交 ee377195 内、调用链存活（runReconcile 经 reconcileIsland 调用、noteStat 经 image(for:) 调用），非漏编。
- WebEffect chunk 三项 ✓：包内 WebEffect/assets/providerRegistry-*.js 与 _redirects 均含 /api/netease、/api/qq、/api/kugou。

## 六项落地（均为「代码已改＋验包已过」，真机未验）

1. **灵动岛宠物**：旧实现没生效根因（代码＋(71) 日志双实证）——上岛唯一路径为墙台收台告别→分流抽签→三道闸，(43) 活泼序选角与 (53) 固定双人组闸口径相反，双人组几乎永不入选；抽样会话台上 cast=0、pet.move / pet.farewell.dest 全程 0 次。新实现：PetHomeRegistry.reconcileIsland(reason:)（0.5s 合并去抖），在稳定事件触发（intro 入场完成 / active scene 激活 / switch 开关切换 / concert 演唱会结束 / farewell 告别完成），双人组（cat-live 恒左＋dog-11 恒右）默认家=岛、确定性落座；pickAssets 返回前打 3 秒过期 claim 防抢人；PetConcertRelocation begin 先置 islandSuspended、end 清旗后 reconcile；prepareFarewellDestinations 废 (43) 构成/活泼序、只放行双人组；岛层补 onIslandArrival 执行口（与 onIslandDeparture 对称）。自证面包屑：isl.boot / isl.gate / isl.seat.ok / isl.seat.no / isl.drive（均 ≤15 字节名）。全局关只撤岛民（home==.island），台上双人组归台上 dismiss 流。
   - DS 对抗评审一轮（deepseek-flash）：问题稿 forensics/ds-review-2026-11-22-r72-island-question.md、原文 ds-review-2026-11-22-r72-island-answer-raw.txt、对账 ds-review-2026-11-22-r72-island-reconcile.md。采纳：稳定事件触发、claim 防抢、裁决/执行分离、冷启等入场信号、演唱会门控、自证补强。顶回：DS「双人组移出自动选角池/租借制」属产品变更越界（Miller 定版为三地流转）；全面状态机改造成本不成比例（全仓主线程串行）。
2. **切歌卡顿**：QueueManager.prefetchUpcoming()——每次装载成功后预热可预判下一首（loopAll 取模 / off 未到末尾；shuffle、repeatOne 跳过）的取流（prefetchStream）＋歌词（LyricRepository.entry）＋封面（低优先级），与智能过渡开关无关；WallLayout 滚动中（dragging/decelerating/tracking）禁止 rebase、记 pendingRebase、停滚 0.18s 后 flush（面包屑 wall.rebase.dfr），漂移超限先做实例集覆盖实测（visibleRectCoveredByInstances）、覆盖足只前移锚点不重算，纯尺寸类别变（旋转）且数据键不变且非有限模式时不全量重算；LocalServer 新增 listenerAlive 真活标志＋waitUntilAlive（根因：failed 后 port 不清零、同端口 1 秒重试空窗里 waitUntilReady 误判活），NativeDataClient 与 NativeCoverLoader 遇 -1004 时 start()＋等真活＋整请求重发一次；新建 MiniBarSingleHost 单宿主仲裁（claim/release/isActive＋sharedCollapsed），HomeWall（homewall）与 WallPrototype（wallproto）两宿主的收/展加非认领短路、形态同步共享旗标、认领时无动画对齐。
3. **Lattice 状态**：病根——(71) 的 now 态只有序号牌数字染色、tile 本体无变化，肉眼等于没亮。QueueLatticeCell 新增 accent 环（3pt 描边＋光晕，播放中呼吸脉冲）、序号牌反转为 accent 底黑字、played 压暗 0.38→0.42 且文案同步压暗；VC 新增 enginePlaying 订阅刷新与 refreshVisiblePlaybackStates / lattice.state 自证面包屑。
4. **爪印钮全局＋弱化**：PetSummonButton70 加 0.5s 序位守护（.common）恒提窗口最上（病根：它是窗口子视图，presented 页后入窗即盖住、只在主页够得着）；直径 44→36、静置 alpha 0.55→0.35、圆底 0.35→0.22、右边距 14→8；长按 2s 召唤 / 3s 告别语义不变；开关都触发 reconcileIsland("switch")。
5. **灯泡钮透明底**：WB62HomeWallHooks 的 ponder 钮撤紫蓝底（原 0.545,0.486,0.941,0.85）改 .clear，白字形＋黑色柔影保可读性。
6. **歌单页封面**：NativeCoverLoader 加在途合并（同 URL 一份 Task）、LoadScheduler actor 优先级调度（在途网络取图 ≤4、visible＞prefetch）、解码顺带算 1px 平均色入 colorCache、dominantColorAnyTier / placeholderColor（哈希暗调色）占位、cvr.stat 每 40 次网络取图汇总；WallPosterCell 与 QueueLatticeCell 无图时垫主色块不许纯黑、出图清底色；WallPrototype 预取与 QueueManager 封面预热走 .prefetch。

## iOS 适配自查

- 横竖屏：本版未改布局几何；墙 rebase 延后逻辑对旋转单独放行（尺寸类别变走原路径），迷你台单宿主不改既有横竖同尺寸规格。
- 安全区/灵动岛：爪印钮提层后仍在原安全区位置（右边距 8）；灵动岛落座沿既有障眼法规格（岛位几何未动）。
- 系统手势：爪印钮序位守护只提层不拦截手势；单宿主仲裁只短路非认领宿主的收展调用，不改手势识别。
- 深色外观：灯泡钮透明底＋白字形＋黑柔影，深浅两色下均可读；封面占位色为暗调低饱和，深浅两色下均不刺眼。
- 目标机型 iPhone 14 Pro：无机型专属 API 新增。

## 未定案项

- 六项全部待 Miller 真机验收（本报告只到「代码已改＋CI 成功＋验包已过」）。
- 上传待补：需重新触发 remote-storage 上传并由 Miller 点审批卡。
- 双击闪退（(63) 本体从未宣称已修）与汪汪队横屏半幅仍未定案，等下次真机日志。
- 歌词与声音同步根治未含于本版（仍排队，等 (67) §0 量测）。
