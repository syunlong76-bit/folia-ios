# Folia iOS 套壳工程

Folia 播放器的 iOS 版套壳：前端全量内置在 app 包内，由 app 内置的本地 HTTP 服务器提供，
WKWebView 全屏加载。与安卓内置版**严格同构**——同一套前端、同一个更新清单、同一套版本切换逻辑。

> **状态：未编译验证。** 本工程在无 Xcode 的 Linux 环境下编写完成，未经过任何编译。
> 首次云端构建即是编译测试，请对照文末「首跑排查清单」逐项看日志，不要预期一次通过。

---

## 工程结构

```
ios-shell/
├── project.yml                  # XcodeGen 工程描述（bundle id、部署目标、依赖、源文件）
├── Info.plist                   # XML 手写，含 ATS 本地网络例外配置
├── Sources/
│   ├── AppDelegate.swift        # @main 入口
│   ├── SceneDelegate.swift      # 建窗口；冷启动流程：备 WebRoot → 主界面 → 自动检查更新
│   ├── MainViewController.swift # 全屏 WKWebView + 右边缘半透明齿轮按钮
│   ├── SettingsViewController.swift  # 原生设置页（版本信息/自动更新开关/检查更新）
│   ├── LocalServer.swift        # NWListener 本地服务器：静态文件 + /sw.js stub + /api 代理
│   ├── WebRootManager.swift     # 版本目录管理：首次拷贝 v1、pending 切换、旧版清理
│   └── UpdateManager.swift      # 更新清单拉取、zip 下载、SHA-256 校验、解压落位
├── Resources/
│   └── Web/                     # 前端全量文件（= folia-major/dist，已剔除 icon.svg.bak）
│                                # 在 project.yml 中以 folder reference 打进 app 包
└── .github/workflows/
    └── build-ipa.yml            # 云端构建：产出未签名 IPA
```

- Bundle ID：`com.miller.folia`
- 部署目标：iOS 16.0，Swift 5
- 唯一第三方依赖：ZIPFoundation（Swift Package，project.yml 中声明）

## 架构（与安卓版同构）

```
┌──────────────────────────── Folia.app ────────────────────────────┐
│  WKWebView ── http://127.0.0.1:18765 ──► LocalServer (NWListener) │
│                                            ├─ 静态文件 ◄─ Documents/web/v{n}（当前生效版本）
│                                            ├─ /sw.js → 自注销 stub
│                                            └─ /api/* ── URLSession 代理 ──► https://folia-music.netlify.app
│  UpdateManager ── 拉 app-update.json ──► 下载 zip → 校验 sha256 → 解压 → 记 pending
│  WebRootManager ── 冷启动时：pending 完整且版本更高 → 切换生效
└────────────────────────────────────────────────────────────────────┘
```

### 本地服务器

- 监听 `127.0.0.1:18765`，仅绑回环接口（`requiredInterfaceType = .loopback`），不对局域网暴露；
  端口被占时自动 +1 回退，最多试 11 个端口（18765–18775），实际端口在设置页可查。
- 静态根目录 = 当前生效版本目录；带扩展名的缺失文件回真实 404，无扩展名路径回退 `index.html`（SPA 路由）；
  静态响应一律 `Cache-Control: no-cache`，保证整包换版后不吃 WebView 旧缓存。
- `/sw.js` 返回**自注销 stub**：壳内禁用 Folia 自带的 Service Worker（Workbox 预缓存），
  避免它与壳的「整包版本切换」机制互相打架；壳内的离线能力由本地文件本身提供。
  代价：原 SW 内 importScripts 的封面缓存通道（folia-cover-sw.js）在壳内不工作，
  封面走网络/CDN 兜底，首跑时请留意封面显示是否正常。
- `/api/*` 反向代理到站点源：完整转发 method、请求头（含 Cookie）、请求体；
  响应状态、响应头、Set-Cookie、响应体原样回传（Set-Cookie 解析后逐条重发并去掉 Domain 属性，
  使其成为本机源的 host-only cookie）。URLSession 侧禁用了自带 cookie 管理，只做原样转发。
  **不另做 cookie 罐**——本服务器就是 WebView 的源（origin），登录 Cookie 按标准浏览器规则
  在 WebView ↔ 本地服务器之间流转，代理只是把它们原样带给上游。
- 限制：不支持 chunked 请求体（回 501）；Folia 的 API 调用均带 Content-Length，正常不会触发。

### 版本与自动更新

- 包内前端为 v1。首次启动拷贝到 `Documents/web/v1`，UserDefaults 记 `activeWebVersion=1`。
- 更新清单与安卓共用同一份：`https://folia-music.netlify.app/app-update.json`
  （字段：`webVersion` 整数、`url`、`sha256`、`size`；更新 zip 内须为前端文件平铺结构，
  `index.html` 在 zip 根目录）。
- 冷启动（自动更新开关开时）后台检查一次：版本更高 → 下载 → 校验大小与 SHA-256（CryptoKit 流式计算）
  → 解压（ZIPFoundation）→ 完整性校验（index.html 存在）→ 记 `pendingWebVersion`。
  任何一步失败都静默保留旧版，只把结果写进设置页「上次检查结果」。
- 下次冷启动 WebRootManager 发现 pending 完整且版本更高，自动切换生效，并清理更旧的版本目录。
- 设置页（主界面右边缘垂直居中的半透明齿轮）：壳版本、当前/待生效前端版本、本地服务端口、
  上次检查结果、自动更新开关（默认开）、「检查更新」按钮；
  有 pending 时显示「重启应用新版本」按钮，点击弹出说明引导用户关闭重开（不强杀进程）。

### 本地服务器与 ATS（Info.plist 依据）

WKWebView 加载 `http://127.0.0.1:<port>` 需要 ATS 放行本地明文 HTTP，Info.plist 已配：

- `NSAppTransportSecurity.NSAllowsLocalNetworking = true`——苹果为本地网络（含回环）提供的
  ATS 例外开关，专为「app 访问本地网络资源」场景设置；
- 同时为 `127.0.0.1`、`localhost` 显式声明 `NSExceptionAllowsInsecureHTTPLoads = true`，双保险。
- WebKit 视回环地址为 potentially trustworthy origin（安全上下文），
  localStorage / IndexedDB 等能力不受 http 影响。
- 对外流量全部 HTTPS（/api 代理走 URLSession、音频与封面走平台 CDN），不设 `NSAllowsArbitraryLoads`。

## 云端构建（GitHub Actions）

本机无 Mac/Xcode，构建走 GitHub Actions 的 macOS runner：

1. 把本目录（含 `.github/`）推到一个 GitHub 仓库；
2. 打开仓库 Actions 页 → `Build unsigned IPA` → Run workflow（push 到 main 也会自动触发）；
3. 流水线依次执行：装 XcodeGen → `xcodegen generate` → 解析 Swift 包 → `xcodebuild`
   以 `CODE_SIGNING_ALLOWED=NO` 构建 Release → 把 `.app` 组装成 `Payload/` 打成未签名 IPA；
4. 在该次运行的 Artifacts 里下载 `Folia-unsigned-ipa`，得到 `Folia-unsigned.ipa`。

IPA 是**未签名**的，不能直接装机；签名在安装环节完成（下一节）。

## 签名安装路线

### 首选：SideStore（自己的 Apple ID，免费）

- 原理：用你自己的 Apple ID 给 IPA 做个人签名，证书 7 天有效；
  SideStore 装在手机上后可**在手机本地自动续签**，日常无感。
- 首次安装需要一台电脑配合一次：用电脑给手机生成配对文件（pairing file）并完成 SideStore 的首次侧载；
  之后续签、装新 IPA 都在手机上完成。
- 限制：免费 Apple ID 同时最多保留 3 个侧载应用、每 7 天的签名次数有限额，自用足够。

### 备选：自有开发者账号（$99/年）

- 加入 Apple Developer Program 后，用自己的证书签名，**一年有效**、无 3 个应用限制，
  也可以走 TestFlight 分发给朋友测试。最省心，但每年付费。

### 不推荐：企业证书路线

网上流传的「企业签」「全能签」类服务用的是泄露/倒卖的苹果企业开发者证书：

- 苹果随时吊销，一吊销所有用该证书装的应用**集体打不开**，且毫无预兆；
- IPA 要经他人服务器签名，来路与完整性无法验证，你的平台账号要在里面登录，风险自担；
- 教程站自己都承认免费证书随时失效、转而推销付费版。

**结论：只用自己的 Apple ID（SideStore）或自己的开发者账号签名，不碰来路不明的证书与 IPA。**

## 首跑排查清单（首次云端构建 & 首次装机）

构建阶段（Actions 日志）：

- [ ] `xcodegen generate` 是否成功（project.yml 语法/路径问题看这里）
- [ ] ZIPFoundation 是否解析成功（SPM 拉取失败多为网络/版本约束问题）
- [ ] Swift 编译报错逐条修：本工程未经编译，**首跑大概率有若干语法/ API 用法错误**，
      按日志逐个改 `Sources/` 对应文件后重新 push
- [ ] 构建产物路径是否为 `build/DD/Build/Products/Release-iphoneos/Folia.app`
      （若 Xcode 版本不同导致路径变化，改 workflow 的 Package 步）
- [ ] 产物 IPA 里是否包含 `Web/` 文件夹（folder reference 是否生效：
      解开 IPA 看 `Payload/Folia.app/Web/index.html` 是否存在）

装机运行阶段：

- [ ] 首屏能否打开（本地服务器是否监听成功；设置页可看实际端口）
- [ ] 若白屏：先查 ATS（见上文）与 WebView 加载错误提示，再查端口是否被占回退
- [ ] 三平台扫码登录、搜索、歌单、播放是否与网页版一致（走 /api 代理）
- [ ] 登录是否持久（关 app 重开仍登录：Cookie 链路 = WebView ↔ 本地服务器 ↔ 代理上游）
- [ ] 封面图显示是否正常（壳内 SW 封面缓存通道关闭后的兜底情况）
- [ ] 设置页齿轮可点、开关持久、手动「检查更新」结果字符串正常
- [ ] 发布一个 v2 更新包并改线上清单后，冷启动能否自动下载、再冷启动能否切换生效

## 与安卓版的对应关系

| 能力 | 安卓版 | iOS 版（本工程） |
|---|---|---|
| 本地服务器 | 壳内嵌 HTTP 服务，127.0.0.1:18765 | NWListener，127.0.0.1:18765（同端口策略） |
| WebView 源 | 本机回环地址 | 本机回环地址（同一设计） |
| /api 代理 | 转发到同一站点源 | URLSession 转发到同一站点源 |
| /sw.js | 自注销 stub | 自注销 stub（同一段脚本） |
| 更新清单 | 同一份 app-update.json | 同一份 app-update.json |
| 版本切换 | pending + 冷启动切换 | pending + 冷启动切换（WebRootManager） |
| 设置入口 | 齿轮按钮 → 原生设置 | 齿轮按钮 → UIKit 设置页 |
