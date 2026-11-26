# 对账：QQ / 酷狗头像字段（(92) 修复预研，只读）

方法：对照移植先查数据通路——以**已跑通的网页版解析**为准，往上追
**EdgeOne 函数出口形态**（函数是否裁剪/改名决定字段以哪一层为准），
再与原生候选逐项对账。结论分「定案」（有代码证据）与「推测」
（需真机实回包）两档，不编造字段名。

先说总裁决，两家结论完全不同：

- **QQ：字段没有错。** 原生候选与网页版逐字一致、顺序一致
  （定案）。QQ 头像缺失不是字段名问题，不要在 (92) 里改 QQ 的
  字段候选——病根在审计已定性的落盘/自愈链（合并语义＋envelope
  无头像＋自愈入口太深）。是否还存在「该账号实回里根本没有头像」
  的可能，只能靠面包屑抓实回定案（见 §1.4）。
- **酷狗：字段大体对齐，但有三处实差（定案）。** 候选集漏了网页版
  优先取的一组封面族字段、优先级与网页版相反、且**整段 URL
  后处理缺失**——最后一处能独立造成「字段解析到了、头像就是
  显不出来」，与真机症状吻合（机制定案；实回值的具体形态
  属推测，见 §2.4）。

---

## 1. QQ

### 1.1 函数出口形态（定案）

- EdgeOne 入口 `edgeone-qq/cloud-functions/[[default]].js` 是薄适配层：
  Express 请求原样转给 `@yakult-green-tea/qq-music-api` 的 serverless
  handler（文件头注释 :8-14 自陈「The real path … is forwarded
  untouched」），**函数层对 /login/status 不做任何字段加工**。
- 该包的 /login/status 路由
  （`folia-major/node_modules/@yakult-green-tea/qq-music-api/dist/src/routes/operations/loginStatus.js` 全文）：
  出口恒为 `{ code: 200, data: profile ? { profile } : {} }`。
- profile 的构造（同包 `dist/src/services/auth/authenticatedReads.js`）：
  `getLoginProfile`（:90-94）= **凭据兜底层在下、上游实回在上**合并：
  - 兜底层 `publicProfileFromCredential`（:66-78）：把
    `credential.logo || credential.avatarUrl` **改名**为顶层
    `avatarUrl` 输出（:70、:74），同时给出已解析的
    `musicid`/`str_musicid`（走 credentialMusicId，永不给微信
    占位 `0`）与 `nickname`/`nick`。
  - 上游层 = `GetLoginUserInfo` 原始响应（经 sanitizePublicValue）。
    包内注释（:82-89）实测记录：其顶层键只有 errMsg / identify /
    info / celebrityInfo 等，**全部账号字段都在嵌套 `info` 下，
    整个响应里没有 musicid/uin**。
- 所以函数出口 `data.profile` 里头像有**两个合法来源**：
  顶层 `profile.avatarUrl`（兜底层改名而来）与
  `profile.info.logo`（上游原名）。网页版注释把这点写死了
  （qqNormalize.ts:205-207）：「头像在 `info.logo`，是一条完整的
  https URL（`.../qqmusic/avatar/<hash>-<ts>/140`），上游整个响应里
  没有 `avatarUrl` 这个名字——那是后端凭据兜底路径给的字段名」。

### 1.2 网页版解析（定案，基准）

`folia-major/src/services/onlineMusic/qq/qqNormalize.ts`
`normalizeQqUser`（:185-220），调用点 qqProvider.ts:518-525
（`requestQq('login_status')` → 取 `response.data.profile` 解析）：

| 字段 | 网页版候选（逐字） | 出处 |
|---|---|---|
| 头像 | `profile.avatarUrl` ?? `info.logo` ?? `info.avatarUrl` | qqNormalize.ts:208 |
| 昵称 | `profile.(nickname\|nick\|name\|userName)` ?? `info.(同组)` | qqNormalize.ts:201-204 |
| ID | `profile.(str_musicid\|musicid\|uin\|id)` ?? `info.(str_musicid\|musicid\|uin)`，且跳过占位值 `'0'` | qqNormalize.ts:198-199、:176-183 |

注：昵称候选的注释（:200）记「验收测试账号一个都没回」——
即网页版在该账号上昵称同样为空，profile 在场本身才是登录信号
（qqProvider.ts:531-535 同口径）。

### 1.3 原生对账（定案：逐项一致）

原生 `QQLoginClient.fetchLoginStatus`
（`Sources/Native/Features/Auth/QQLoginClient.swift:136-157`）：
信封拆解 `dataObject(root)["profile"]`（ProviderLoginTransport.swift:166）
与出口形态一致；三组候选与网页版**字段名、顺序全同**
（ID :148-150、昵称 :151-153、头像 :154-155
`profile["avatarUrl"] ?? info["logo","avatarUrl"]`）。

唯一差异（定案，但与头像无关、风险近零）：网页版 ID 解析跳过
占位 `'0'`（微信凭据 musicid 是占位、真 ID 只在 str_musicid），
原生 `stringValue`（ProviderLoginTransport.swift:172-180）不跳。
但函数出口处兜底层给的 musicid 已是解析后的真 ID、上游层根本
不带 musicid，该占位在出口不可达——**不是现行 bug 的成因**，
(92) 不必为它动 QQ 解析；若顺手对齐，加一行 `'0'` 跳过即可。

**结论：QQ 头像字段对账无差异。** 审计 §3.2 的两个缺口定案
（envelope 不带头像、合并语义下解析不到即恒 nil）仍然成立，
但「解析不到」的原因不在字段候选写错。

### 1.4 QQ 未定案（只能靠实回）

兜底层与上游层任一有头像，网页与原生都取得到。若 Miller 的 QQ
账号实回里**两层都没有**（如某些登录通道的凭据不带 logo、且
GetLoginUserInfo 的 info.logo 对该账号为空），则网页版同样显
占位——此时真机症状与解析无关。区分只能靠 (92) 面包屑：
fetchLoginStatus 里落一条「命中的候选键名＋两层有无」即可
（只记键名与有无，不记 URL 与账号值）。

---

## 2. 酷狗

### 2.1 函数出口形态（定案）

- EdgeOne 入口 `edgeone-kugou/cloud-functions/[[default]].js` 把请求
  交给上游 KuGouMusicApi 的 server 本体（kg-server.cjs），路由表
  由 `cloud-functions/kg-modules.js` 静态复刻：`/user/detail`
  在 :210（模块 user_detail.js）、`/user/vip/detail` 在 :200。
- `kugoumusicapi/module/user_detail.js`（edgeone-kugou/node_modules
  内同版）全文：组装参数后 POST 上游 usercenter 的
  `/v3/get_my_info`，**响应原样透传，不裁剪不改名**。
- 信封拆解两边等价：网页版 `dataOf = raw?.data ?? raw?.body?.data
  ?? raw?.body ?? raw`（kugouProvider.ts:70）；原生
  `dataObject` 先剥 body 再取 data
  （ProviderLoginTransport.swift:166-169）——对 user_info 的
  落点无影响。

### 2.2 网页版解析（定案，基准）

`folia-major/src/services/onlineMusic/kugou/kugouProvider.ts`
`normalizeUser`（:485-497），调用点 getLoginStatus（:1366，
`requestKugou('user_detail')`）：

| 字段 | 网页版（逐字） | 出处 |
|---|---|---|
| profile 容器 | `data.user_info ?? data.userinfo ?? data.profile ?? data` | :487 |
| 昵称 | `nickname \| nick_name \| username \| name` | :492 |
| 头像 | `coverOf(profile) \|\| valueOf(profile, 'avatar', 'pic')` | :493 |
| ID | `userid \| user_id \| id \| uid` | :488-490 |
| VIP（初值） | `vip_type \| vipType \| is_vip` | :495 |

其中 `coverOf(profile)`（:100-113）对 profile 本体按序试：
`sizable_cover → Image → image → img → pic → picUrl → cover →
coverUrl → sizable_avatar`，且命中后**必做 URL 后处理**：
`{size}` 替换为 1024（KUGOU_CANONICAL_COVER_SIZE，:51）、
裸文件名（`^\d{8,}\.(jpe?g|png|webp)$`）拼成
`https://c1.kgimg.com/stdmusic/1024/<前8位日期>/<文件名>`、
`//` 补 https:、http: 升 https:，再过 getSizedCoverUrl
（`src/utils/coverUrl.ts:170`）。

### 2.3 原生对账（定案：三处实差）

原生 `KugouLoginClient.fetchUserDetail`
（`Sources/Native/Features/Auth/KugouLoginClient.swift:265-289`）：
容器（:277-279）与昵称（:279-280）、ID（:283-284）候选与网页版
一致。头像只有一行（:281-282）：
`profile["avatar" | "pic" | "sizable_avatar" | "picUrl"]`，原样存。

| # | 差异 | 网页版 | 原生 | 影响 |
|---|---|---|---|---|
| 1 | 候选集不全 | coverOf 的 9 个键（含 `sizable_cover`、`Image/image/img`、`cover/coverUrl`）＋ avatar/pic 兜底 | 只有 avatar/pic/sizable_avatar/picUrl 4 个 | 实回若只在漏掉的键下，原生恒 nil、网页版有图（定案为代码差；实回用哪个键属推测） |
| 2 | 优先级相反 | 封面族字段优先，avatar 最后兜底 | avatar 第一顺位 | 两边都取得到时选的图不同（画质/形态差）；单独不造成缺失 |
| 3 | **无 URL 后处理** | {size} 替换、裸文件名拼 URL、http→https、尺寸改写 | 解析与渲染链均无等价物：saveProfile 存原串，`WorkbenchCover.loadAvatar`（WorkbenchCommon.swift:48-95）按原串取图 | 实回值若是 {size} 模板或 http 串，原生「解析成功」但永远加载失败——与「头像不见了」的症状完全吻合（机制定案；实回形态属推测） |

对账外顺带发现（与头像无关，仅记录）：网页版 getLoginStatus 以
「id 与昵称同时有」才认登录（kugouProvider.ts:1385），原生是
昵称或 ID 任一有即认（KugouLoginClient.swift:285-287）。

### 2.4 酷狗未定案（只能靠实回）

`get_my_info` 的 user_info 实回里头像到底在哪个键、是什么形态
（完整 https / {size} 模板 / http / 裸文件名），网页版与函数
源码都证明不了——coverOf 的候选与后处理是网页版作者按实测
攒的，但没有留下针对 user_info 的逐字记录。(92) 修法建议
按已定案的代码差先行：**把 coverOf 的候选集、优先级与 URL
后处理整体移植到原生 fetchUserDetail**（这是对齐已跑通实现，
不依赖抓包结论）；同时加面包屑记「命中的键名＋值的形态分类
（https/http/模板/裸文件名/缺失）」，真机一跑即可把本节
推测定案。

---

## 3. VIP（顺带核，三家全定案）

审计定案「原生三家 LoginProfile 与资料缓存均无 VIP 字段」不变。
网页版三家都有，数据通路各不相同，原生要补显示须按家取数：

| 家 | VIP 在哪 | 取值 | 证据 |
|---|---|---|---|
| 网易云 | 登录资料 profile 自带 `vipType`，normalizeUser 直读（头像同理直读 `avatarUrl`，且 netease.ts:759/768 对头像做 http→https） | 数字（0=免费，>0 为会员等级） | neteaseProvider.ts:76-82 |
| QQ | **不在登录资料里**，独立端点 GET `/user/vip`（qqTransport.ts:87）。后端 userVip 操作出口 `data = { isVip, vipLevel, upstream }`，vipLevel 由 HugeVip/iVipFlag 推导（HugeVip=1→super；=0 时 iVipFlag=1→green、0→free；其余 unknown） | 网页版映射 free→0、green（绿钻）→1、super（超级会员）→2，unknown 则不填（不当免费） | 后端 `services/user/vip.js:69-77`（userVipResult）、`vipLevelOf` 同文件；网页版 qqAccount.ts:7、:26-60（每账号只读一次、登录检查最多等 3 秒） |
| 酷狗 | 两路：user/detail 资料内 `vip_type\|vipType\|is_vip`（初值）＋独立端点 GET `/user/vip/detail`（kg-modules.js:200）复核覆盖，其 data 认 `vip_type\|vipType\|is_vip` 或 `busi_vip[]` 条目的 `is_vip/vip_type` | 数字，>0 即会员 | kugouProvider.ts:495、:500-507（normalizeKugouVipType）、:1366-1376（getLoginStatus 复核段） |

展示口径（网页版）：账户页昵称旁一枚皇冠图标，条件仅
`vipType != 0`，三家通用（`src/components/panelTab/AccountTab.tsx:107-109`）。

原生补 VIP 的数据来源即上表：网易云从现行 /login/status 的
profile 顺手多读一个 `vipType` 键即可（通路现成、零新请求）；
QQ 需新增一次 `/user/vip` 请求读 `vipLevel` 字符串再映射；
酷狗先读资料内三键、再按需调 `/user/vip/detail` 复核。三家都需
给 LoginProfile 与 NativeSessionStore 资料缓存加字段——属 (92)
施工决策，本预研只给通路。

---

## 4. 给 (92) 的结论清单

1. **QQ 解析一个字段都不用改**（定案）。QQ 头像问题按审计的
   落盘/自愈链修；另加一条候选命中面包屑，把 §1.4 的推测
   在真机上定案。
2. **酷狗按网页版 coverOf 整体对齐**（定案的代码差）：候选集
   补全 9 键＋优先级改回封面族优先＋移植 URL 后处理
   （{size}→1024、裸文件名拼 c1.kgimg.com、http→https）。
   加形态分类面包屑把 §2.4 定案。
3. **VIP 三家通路已摸清**（定案），补不补、何时补由 (92)
   施工单决定，数据来源见 §3 表。
