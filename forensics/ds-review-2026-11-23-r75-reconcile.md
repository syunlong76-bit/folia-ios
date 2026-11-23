# DS 评审对账（(75) Live Activity，第一轮空答＋第二轮全量重发，deepseek-v4-pro）

DS 总评：不能按原计划原样施工；改掉三处致命点后可施工。逐条对账（Muse 拍板）：

## 采纳
1. 【致命·A】v1 删除 App Group entitlement——采纳。简报自认 v1 渲染不依赖共享容器；个人团队/SideStore 重签时自选 group id 大概率注册失败（装不上/活动拉不起）。图打进扩展包内即够。与任务书「App Group 齐全」冲突处以此为准，报告中明示偏离及理由；动态图需求出现时再以团队前缀 id 引入。
2. 【致命·G】甲案——采纳。LA 拉起与 miniPetsEnabled、introDone 完全解耦；拉起条件＝areActivitiesEnabled && currentTrack != nil && 非演唱会 && (scene 已激活 || 正在播放)。任何被挡落 la.gate reason=（activitiesDisabled/noTrack/concertSuspended/alreadyActive），不静默。
3. 【致命·E】首拉必须有 currentTrack——采纳（并入上条条件）。
4. 【重要·C】互斥归单一协调器——采纳：IslandLiveActivityManager 独占 perchSuppressed 状态与串行出入口，监听 activityStateUpdates 清抑制；PetIslandLayer 不自查 Activity.activities。
5. 【重要·B】staleDate 分态——采纳改良：播放中 update 刷新 staleDate=now+8h；暂停设 now+15min。更新合并：切歌/播放态/换词同源一次 update。演唱会 resume 加 1s 防抖。
6. 【重要·D】compact 图用 scaledToFit 小框——采纳方向：已抽首帧静态图，compact 内以 fit 框呈现，不复用原图直塞。
7. 【重要·E】phrase 只作 best-effort、与歌名/播放态同源同次 update——采纳，不单独为换词发 update。
8. 【重要·F】监听 activityStateUpdates；纠正 API 误解——采纳：ActivityState 无 .stale（只有 active/ended/dismissed），回前台检查按 ended/dismissed/空 判定。
9. 【重要·F】request 只在前台发——采纳：后台只 update 已有活动，无活动则等下次回前台。
10. 【次要·C】删 petsHidden/EmptyView 兜底——采纳：ContentState 不设 petsHidden，演唱会只走 end 路径。
11. 【次要·工程】扩展 Info.plist 在 project.yml 显式配置并验包——采纳。
12. 【次要·D】锁屏呈现独立可用——采纳（ActivityConfiguration 锁屏 builder 独立成版）。

## 顶回 / 打折
- DS 担心演唱会 end+request 撞系统限频：演唱会是低频用户显式行为，end/request 各一次，加防抖即可，不构成阻塞（其 B 条其余部分已采纳）。
- DS 建议设置页加 LA 说明/跳转：v1 不做（自动回落＋面包屑已够），记为后续项，不占本版面。

## 与第 4 项（拖拽换住）的合流裁决
- LA 永不读 miniPetsEnabled（甲案）；拖拽落座是用户显式意图，按 Miller 20:34 口径：拖拽成功时双写 miniPetsEnabled=true（与爪印召唤同路）＋面包屑自证——这是「视为开启」的落点，不是 LA 的闸。
- 住客名单（左右宠物 id）进 ContentState；名单变更由登记表单一出口通知 manager 更新活动。
