# 日志诊断：(75) 施工期两轮真机日志（2026-11-23 20:34–20:42 CST）

来源：
- `~/workspace/user/files/upload-645896ee.txt`（1201 行；本会话 20:34:59–20:38:51，line 202 起）
- `~/workspace/user/files/upload-af596d0b.txt`（1201 行；本会话 20:38:53–20:42:06，line 202 起）
- 前一份：`upload-7f7dd471.txt`（(74) 会话，20:17–20:24），见 `log-diagnosis-2026-11-23-74session.md`

## 实锤

### 1. 细条点按：歌单页通、主页断在最前端
- 本轮 1：歌单页（wallproto）细条点按 3 次（20:35:08 / 20:35:23 / 20:36:05），
  每次 `minibar.hit via=agnostic74` → `minibar expand` → `form collapsed=0 h=70`，链路通。
  20:35:23 展开后另有 `minibar.seek via=seek-tap`（进度区点按正常）。
- 主页（homewall）细条在两份日志里**零 minibar.hit**；本轮 1 仅 20:38:43 出现一次
  `minibar.form host=homewall collapsed=1 h=16`，其后无点按记录。
- Miller 点不开的时间点（约 20:29–20:34）落在两份日志之间的空档，页面为主页。
- 定案方向：主页细条命中链断在最前端（点按未被识别器接收），与歌单页不是同一个病。
  (74) 的 agnosticTap74 只在 wallproto 上被验证过，被误推为全宿主。
- (75) 处置：第 5 项②——三宿主分环埋点 `minibar.touch75`（到达环）＋`minibar.dead75 at=`
  （几何/标志/仲裁三静默守卫全落痕），下轮日志一次判清死在哪一环。

### 2. 爪印召唤：按压零痕迹，台面宠物被陈旧 off 关死
- 两份本轮日志里 pet.btn74 只出现过一次（本轮 2，20:40:14 `entryhide`，可见性事件，
  不是按压）。召唤/按压相关面包屑全程零条；`pet.tick.heartbeat` 全程
  `petsActive=false collapsed=true cast=0`——台面宠物整轮未激活。
- `pet.settings.read src=barPresentation presented=true miniPets=false`（20:39:59、20:40:41），
  `src=appStart miniPets=false`（20:40:13）；`isl.boot ... bar=off` 三次。
- Miller 20:41 长按爪印 2 秒实测仍无宠物；20:42 澄清：没出现的是**点播台上的宠物**。
- 定案（(75) 第 6 项）：miniPets=false 的写入点只有三处——设置开关（唯一真用户决定）、
  爪印 3 秒告别、长按宠物 3 秒（后两为手势关闭语义），**无自动反复写关者**。
  岛侧因 (73) 删了 reconcile 提前返回能自动落座，台侧召唤链没开这个后门。
  修法：召唤全链埋点 `paw.touch75 dn/up`、`paw.act75 stage=`；面层定位 nil 时改走广播兜底，
  各宠物层自查入场，不再静默。

### 3. 设置从歌单页弹回主页：(74) 转发设计实锤
- 本轮 2，20:41:58：`seam.forward action=settings from=WallPrototypeViewController`
  → 20:41:58.801 `wall.seam.settings`，设置在主页打开（`settings.tab` 随后逐页签刷过）。
- Miller 点名不对。(75) 第 7 项：全局面 {settings, avatar, search, guide} 改本页就地
  呈现（performInPlace）；切段/布局/沉浸/Lattice/「…」仍回主页转发。

### 4. 左滑命令面板：本轮零触发
- 两份本轮日志 `shortcuts62.swipeLeft` 计数 0（上一份 (74) 日志有 3 次）。
- (75) 第 2 项仍按 (74) 日志实锤摘除识别器（`swipe75.off` 自证）。

### 5. 岛侧本轮成立
- `isl.perch74 cat-live=92..130 dog-11=262..300 form=pill` 全程在位；
  `pet.chat surface=island a=cat-live b=dog-11`（20:37:44）——岛上宠物在聊天。
- 20:35 Miller 截图：系统「正在播放」活动展开占岛，障眼法宠物被压在系统层之下
  （狗只剩一条边）。层级差，障眼法无解；(75) 第 1 项真 Live Activity 侧验收三条：
  不被系统正在播放长期挤掉／他方在场整齐让位／结束后能回来。

## 未覆盖
- 主页细条点按（待 (75) 新埋点日志复测）。
- QQ/酷狗实扫、町景勾入后切换、舞台手势链（本轮日志 tapchain74 仍 0 次）。
- LocalServer 挂起 8 分钟复活（本轮无挂起场景，未触发）。
