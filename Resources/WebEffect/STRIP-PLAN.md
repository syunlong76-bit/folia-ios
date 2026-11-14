# WebEffect 真实剥离包：folia-major 改动点清单（M2・待协调员批准）

日期：2026-11-14。状态：**未实施**。M2 不改 folia-major 源码，本文件只列改动点，
由协调员定稿后另排期实施。在此之前，`Resources/WebEffect/` 内是 POC 占位壳
（`index.html` + `folia-bridge.js`，自满足“无 transport / 无 `<audio>` /
无 MediaSession / html-body transparent”，但不是 Folia 构建产物）。

## 结论先行

`build-v7/player/`（= 壳内 `Resources/Web` 的 v7 播放构建）是**完整版**：
含 transport 组件字符串（`PlayerBottomBar` 等 10+ 个 chunk 命中）、
`navigator.mediaSession` 注册（`bootstrap-*.js`）、双 `<audio>` deck。
不改 folia-major 源码就拿不到“构建期剔除、产物 0 命中”的剥离版：
运行时 CSS 隐藏只能藏住控件，藏不住字符串、藏不住 `<audio>` 创建、
也拦不住网页自己的 MediaSession 与播放状态机（`folia:track` /
`folia:tick` 这类桥事件，完整版 App 根本不监听）。
所以真实剥离包必须走构建期插件，改动点如下。

## 改动点清单（按实施顺序）

### 1. 新增 Vite 插件 `playerVisualSurfacePlugin()`（`folia-major/vite.config.ts`）
- 仿照现成 `browseSurfacePlugin()`（同文件约 135–200 行，`FOLIA_SURFACE=browse`
  门控）的新插件，门控改为 `FOLIA_SURFACE=player-visual`。
- `base`：该表面构建须用相对路径（`./`）或经壳 LocalServer HTTP 供包，
  否则 `loadFileURL` 下 `/assets/...` 绝对路径解析不到（file:// 根）。
- 构建命令（待实测）：`FOLIA_SURFACE=player-visual npm run build`，
  产物落 `folia-deploy/build-v7/webeffect/`，再拷入 `ios-shell/Resources/WebEffect/`。

### 2. 推荐路线：独立可视化入口（Option A，首选）
- 新增最小入口（如 `src/visual-only/main.tsx` + 对应 `index.html`），只做两件事：
  复用 visualizer 注册表（17 歌词样式 + 6 背景的渲染代码）与歌词组件，
  状态唯一来源是 `window.__FOLIA_BRIDGE__` 事件（state/progress/seek/queue/
  artwork/lyrics/theme/snapshot/renderState/buffering，见 `folia-bridge.js` 頭注）。
- 该入口**不 import** 以下模块（构建期即排除）：
  - transport：`src/components/FloatingPlayerControls.tsx`、
    `src/components/floating-player/PlayerBottomBarPositioner.tsx`、
    `src/components/ProgressBar.tsx`、`src/components/app/overlays/NowPlayingToast.tsx`
  - 音频 deck：`src/App.tsx` 内 `renderAudioDeck`（约 2560 行）渲染的两个 `<audio>`
    元素及 `src/components/app/playback/bridges/usePlaybackAudioBridge.ts`、
    `useTransportCommandRefs.ts` 等音频桥
  - MediaSession：`src/hooks/useMediaSessionBridge.ts`（`navigator.mediaSession`
    `setActionHandler` + metadata）、`src/components/hifi/useHifiMediaSessionKeepAlive.ts`
    （静音 WAV 保活循环）、`src/components/hifi/useHifiMpris.ts`
  - 浏览/搜索/歌单等业务面（只留播放页可视化层）。
- 歌词组件时间源改点：现有歌词高亮读 `<audio>` 元素时间，须改读
  `__FOLIA_BRIDGE__.getInterpolatedTime()`（rAF + `performance.now()` 插值），
  并订阅 `folia:tick` / `folia:track` / `folia:lyrics` 事件。
- 主题：`theme` 事件的 `backgroundMode`（web | native-scene）与 `palette`
  直接驱动莫奈背景；`snapshot` 一次推齐。

### 3. 备选路线：全量 App 内打桩（Option B，不推荐）
- 沿用完整 App 入口，在 `playerVisualSurfacePlugin` 里把 transport/音频 deck/
  MediaSession 模块逐个换成空实现（仿 `browseSurfacePlugin` 换 `SceneHost` 的做法）。
- 风险：全量 App 的播放状态机以自有 `<audio>` 为时间源与事件源，桥事件无处可接；
  桩打不全会残留“网页自己出声 / 与原生锁屏抢 MediaSession”的双音频源。
  只有 Option A 行不通时才评估本路线。

### 4. 产物校验（构建后必跑，命令可复现）
```sh
cd <webeffect 产物目录>
grep -r "PlayerBottomBar\|FloatingPlayerControls\|ProgressBar" assets/ | wc -l  # 预期 0
grep -r "navigator.mediaSession\|setActionHandler" assets/ | wc -l            # 预期 0
grep -r "<audio" assets/ index.html | wc -l                                  # 预期 0
grep -c "data-folia-transport" index.html                                     # 剥离工序人为打标后 >= 1（兜底用）
grep -o "html,body{background[^}]*}" index.html                              # 须含 transparent
```
- 另需：产物内 `folia-bridge.js` 在位且先于业务 bundle 加载；
  `data-folia-transport` 标记由剥离工序人为打上，不假设原 DOM 自带；
  运行期 CSS 对该标记禁交互兜底（占位壳 `index.html` 内已有该条 CSS，可复用）。

## 占位壳与真实包的界线

- 占位壳（已交付）：验证桥协议、快照恢复、歌词行高亮、主题、队列、冻结的整条链路；
  不验证 Folia 特效本身（样式/背景渲染代码不在占位壳里）。
- 真实包（待批）：Option A 落地后，占位壳 `index.html` 替换为真实构建产物，
  `folia-bridge.js` 与桥协议不变；届时重跑上节校验 + 真机冷启动无白闪录屏。

## 与本包无关、不改的点

- `build-v7/player/` 与壳内 `Resources/Web` 不动（旧双表面壳继续用）。
- 不动 Netlify / EdgeOne / 播放 API；歌词仍由原生侧 `EdgeOneAPIClient.fetchLyricText`
  现取后经桥推给页面（桥内已接好，见 `WebEffectBridge.fetchLyricsIfNeeded`）。
