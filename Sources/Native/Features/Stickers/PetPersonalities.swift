import Foundation

// 宠物人格体系（3.7 (32) 细修 5 升级，Miller 2026-11-20 02:06
// 定案）：五种人格原型按每只素材的形象/动作气质分配（分配表
// 见 PetPersonalities.assignment，注释里附依据印象，供 Miller
// 否决调整）。宠物间停聊不再用固定双人剧本，改由本库拼装：
// A 人格按话题开场 → B 以「自己人格 × 该话题」回应 → 可选 A
// 以「自己人格 × 该话题」反应收尾（可选 B 再补一句），共
// 2–4 句，问答由话题对齐保证对得上。量级：开场 5 人格 × 10
// 句 = 50（每人格覆盖 5 话题 × 2）；回应 5 人格 × 5 话题 ×
// 4 = 100；反应 5 人格 × 5 话题 × 2 = 50；全库 200 句。
// Miller 种子句逐字收录于适配人格的开场池：「吃饭了吗」→
// 可爱·关心；「你今天真漂亮」→ 调皮·夸夸；「你好可爱哈哈哈」
// → 爱开玩笑·调侃。

enum PetPersonality: String, CaseIterable {
    case cute, mischievous, melancholy, grumpy, joker

    /// 面包屑/汇报用中文名。
    var label: String {
        switch self {
        case .cute: return "可爱"
        case .mischievous: return "调皮"
        case .melancholy: return "忧郁"
        case .grumpy: return "愤怒"
        case .joker: return "爱开玩笑"
        }
    }
}

enum PetChatTopic: String, CaseIterable {
    case care, praise, tease, play, music

    var label: String {
        switch self {
        case .care: return "关心"
        case .praise: return "夸夸"
        case .tease: return "调侃"
        case .play: return "约玩"
        case .music: return "听歌"
        }
    }
}

enum PetPersonalities {

    /// 人格分配表（53 只全量；分组注释 = 依据的动作印象）。
    static let assignment: [String: PetPersonality] = [
        // 可爱（14）：跳舞/抱抱/爱心/依偎等亲人动作
        "dog-01": .cute,   // 踩着音符跳舞
        "dog-03": .cute,   // 两只贴贴背对
        "dog-05": .cute,   // 小步蹦跶招手
        "dog-08": .cute,   // 抱福字橘子装
        "dog-10": .cute,   // 抱住伙伴
        "dog-11": .cute,   // 抱爱心
        "dog-15": .cute,   // 乖坐捧饮料
        "dog-16": .cute,   // 腮红挥手
        "dog-23": .cute,   // 松鼠装依偎
        "dog-26": .cute,   // 牵手转圈
        "dog-27": .cute,   // 蝴蝶结闪亮
        "cat-12": .cute,   // 带小伙伴同行
        "cat-18": .cute,   // 泪汪汪挥爪
        "cat-live": .cute, // 捂脸摇晃
        // 调皮（9）：捣蛋/恶作剧/灵动动作
        "dog-02": .mischievous, // 站伙伴头顶叠碗
        "dog-12": .mischievous, // 泡澡玩水
        "dog-14": .mischievous, // 守着饭碗偷吃相
        "dog-21": .mischievous, // 乘枫叶飞走
        "cat-06": .mischievous, // 戴鼠耳帽
        "cat-07": .mischievous, // 骑在伙伴背上
        "cat-08": .mischievous, // 翻滚摔跤
        "cat-17": .mischievous, // 拉长身体
        "cat-21": .mischievous, // 墨镜摇头晃脑
        // 忧郁（19）：困倦/垂泪/蜷缩/躺平气质
        "dog-09": .melancholy, // 躺床睡觉
        "dog-13": .melancholy, // 对着电脑发蔫
        "dog-17": .melancholy, // 月夜依偎出神
        "dog-18": .melancholy, // 安静看书
        "dog-22": .melancholy, // 卧读报纸
        "dog-25": .melancholy, // 含泪围兜
        "cat-02": .melancholy, // 蜷成小团垂泪
        "cat-03": .melancholy, // 站立垂泪
        "cat-04": .melancholy, // 单爪抹泪
        "cat-05": .melancholy, // 大脸垂泪特写
        "cat-09": .melancholy, // 若隐若现
        "cat-11": .melancholy, // 一滴泪转圈
        "cat-14": .melancholy, // 躺着刷手机
        "cat-16": .melancholy, // 捂脸哭
        "cat-19": .melancholy, // 躺床玩手机
        "cat-20": .melancholy, // 甩头飙泪（(40) 裁定：大哭归忧郁，非炸毛）
        "cat-22": .melancholy, // 系领带垂泪
        "cat-24": .melancholy, // 躺倒流泪
        "cat-25": .melancholy, // 角落小只独坐
        // 愤怒·傲娇（5）：瞪眼/抱臂/背对/打闹的炸毛感（不伤人）
        "dog-06": .grumpy, // 叼领带一脸得意
        "dog-20": .grumpy, // 端坐臭脸
        "dog-24": .grumpy, // 两只打闹扑咬
        "cat-13": .grumpy, // 背对生闷气
        "cat-23": .grumpy, // 抱臂翘腿大佬坐
        // 爱开玩笑（6）：笑闹/夸张表情
        "dog-04": .joker, // 高频抖头
        "dog-07": .joker, // 举待办清单咧嘴
        "dog-19": .joker, // 沙发爆米花看戏
        "cat-01": .joker, // 哭笑交叉眼
        "cat-10": .joker, // 笑出泪吐舌
        "cat-15": .joker, // 吐舌大笑
    ]

    static func of(_ asset: String) -> PetPersonality {
        assignment[asset] ?? .cute
    }
}

// MARK: - 人格对话库（开场 / 回应 / 反应）

enum PetChat {

    struct Dialogue {
        let topic: PetChatTopic
        /// (是否 A 说, 台词)，交替顺序已排好。
        let lines: [(speakerIsA: Bool, text: String)]
        let openerIndex: Int
        let responseIndex: Int
    }

    /// 拼装一次对话：随机话题（或指定）→ A 人格开场 → B 人格
    /// ×话题回应 → 70% A 反应收尾 → 35% B 再补一句反应。
    static func generate(a: PetPersonality, b: PetPersonality,
                         topic forced: PetChatTopic? = nil) -> Dialogue {
        let topic = forced ?? PetChatTopic.allCases.randomElement() ?? .care
        let openerPool = openers[a]?[topic] ?? []
        let responsePool = responses[b]?[topic] ?? []
        let openerIndex = openerPool.isEmpty ? 0 : Int.random(in: 0..<openerPool.count)
        let responseIndex = responsePool.isEmpty ? 0 : Int.random(in: 0..<responsePool.count)
        var lines: [(Bool, String)] = []
        if !openerPool.isEmpty { lines.append((true, openerPool[openerIndex])) }
        if !responsePool.isEmpty { lines.append((false, responsePool[responseIndex])) }
        if Double.random(in: 0..<1) < 0.7,
           let pool = closers[a]?[topic], !pool.isEmpty {
            lines.append((true, pool.randomElement()!))
        }
        if Double.random(in: 0..<1) < 0.35,
           let pool = closers[b]?[topic], !pool.isEmpty {
            lines.append((false, pool.randomElement()!))
        }
        return Dialogue(topic: topic, lines: lines,
                        openerIndex: openerIndex, responseIndex: responseIndex)
    }

    // MARK: 开场（每人格 10 句：5 话题 × 2）

    static let openers: [PetPersonality: [PetChatTopic: [String]]] = [
        .cute: [
            .care: ["吃饭了吗", "你今天过得怎么样呀"],
            .praise: ["你今天毛毛好顺哦", "你的眼睛亮晶晶的"],
            .tease: ["你刚才是不是偷偷打哈欠啦", "嘿嘿，你尾巴尖在抖哦"],
            .play: ["等会儿陪我玩一会儿好不好", "我们去那边转转吧"],
            .music: ["这首歌好好听呀", "你也喜欢这首吗"],
        ],
        .mischievous: [
            .care: ["喂，你饿不饿？我藏了好吃的", "今天有没有偷偷偷懒呀"],
            .praise: ["你今天真漂亮", "哇，你今天格外精神呢"],
            .tease: ["你是不是又把零食藏起来了", "刚才那下我可都看见了哦"],
            .play: ["走，趁他不注意，我们去探险", "来比赛，看谁先跑到那边"],
            .music: ["这首歌一响，我就想蹦跶", "快听快听，到好听的地方了"],
        ],
        .melancholy: [
            .care: ["你……今天还好吗", "唉，你也睡不够吗"],
            .praise: ["你今天……挺好看的", "你的毛，今天很柔顺"],
            .tease: ["你也是一脸没睡醒的样子", "我们俩……都蔫蔫的"],
            .play: ["要不……就坐着发会儿呆吧", "陪我躺一会儿，就一会儿"],
            .music: ["这首歌，听得我想睡了", "这首慢慢的，适合发呆"],
        ],
        .grumpy: [
            .care: ["哼，你吃东西了没有", "别饿着了，听见没"],
            .praise: ["今天……还算顺眼", "你的毛，勉强算整齐吧"],
            .tease: ["你怎么又慢吞吞的", "看什么看，没见过我生气？"],
            .play: ["要玩就快点，我可不等你", "陪你玩一会儿，就一会儿啊"],
            .music: ["这首，还算能听", "别切，这首我勉强喜欢"],
        ],
        .joker: [
            .care: ["干饭时间到，你准备好了吗", "听说今天有好吃的，真的假的"],
            .praise: ["哇，你今天闪闪发光", "你这造型，可以出道了"],
            .tease: ["你好可爱哈哈哈", "你刚才的表情，我能笑一天"],
            .play: ["走走走，快乐这不就来了", "我有个好玩的主意，听不听"],
            .music: ["这首一响，我的脚就不听话了", "前方高能，好听的部分来了"],
        ],
    ]

    // MARK: 回应（每人格 × 每话题 4 句；必须真回应开场话题）

    static let responses: [PetPersonality: [PetChatTopic: [String]]] = [
        .cute: [
            .care: ["吃了吃了，你呢", "嗯，我有乖乖吃饭哦", "还不错，有你在就更好啦", "吃饱啦，还打了个小盹"],
            .praise: ["真的吗？谢谢你", "嘿嘿，你也很好看呀", "被你夸得我都脸红啦", "那我以后天天这样"],
            .tease: ["哪有啦，被你发现了", "嘿嘿，就一下下", "你不许笑我啦", "那你陪我一起嘛"],
            .play: ["好呀好呀，我都等不及了", "嗯！我陪你去", "玩什么都行，跟你一起就好", "拉钩，不许反悔哦"],
            .music: ["嗯嗯，我也好喜欢", "这首听到心里去了", "我陪你一起听完", "好听，我都想跟着晃了"],
        ],
        .mischievous: [
            .care: ["吃了，还偷吃了一口你的", "饿着呢，快分我一口", "我吃饱了，还藏了一份", "你猜？我不告诉你"],
            .praise: ["嘿嘿，那是当然", "眼光不错嘛", "再夸一句，我就飘了", "低调低调……继续夸也行"],
            .tease: ["被发现了？那就一起吃", "嘘——你也来一口", "我才没有，是它自己掉我嘴里的", "看见了也不许说出去哦"],
            .play: ["走！我带路", "比就比，输了不许哭", "探险！我最喜欢了", "等等我，我先藏好零食"],
            .music: ["我已经蹦起来了", "这段我能循环一百遍", "快，跟上节奏", "听得我尾巴停不下来"],
        ],
        .melancholy: [
            .care: ["吃了……一点点", "还没……不太想动", "嗯，还好，就是困", "你先吃吧，我躺会儿"],
            .praise: ["啊……谢谢，有点不好意思", "哪有……你别哄我", "嗯……听了心里暖一点了", "真的吗……那我开心一下"],
            .tease: ["嗯……被你看出来了", "唉，连哈欠都藏不住", "你不也一样嘛……", "别笑我，我已经很努力醒着了"],
            .play: ["可以……慢慢走就行", "我跟在你后面，好吗", "玩一会儿，我就回来躺着", "嗯，你拉我一把"],
            .music: ["嗯……这首好温柔", "听着听着，就想睡了", "别切，让它放完吧", "这首，陪我慢慢听"],
        ],
        .grumpy: [
            .care: ["吃了！不用你操心", "哼，还知道关心我", "没吃……你有好吃的？", "饿不着，倒是你，别光顾着听歌"],
            .praise: ["哼，那还用说", "少来……不过，谢谢", "就、就你眼睛尖", "别夸了，我会当真的"],
            .tease: ["谁、谁偷吃了！", "哼，看见了又怎样", "你才慢吞吞", "再说，我可要生气了"],
            .play: ["来就来，谁怕谁", "哼，勉强陪你", "输了可不许耍赖", "就玩一会儿，多了不行"],
            .music: ["哼，还行吧", "这首……凑合", "别切歌，听完再说", "就这首吧，我懒得挑了"],
        ],
        .joker: [
            .care: ["吃了三碗！还想吃", "干饭我是专业的", "刚吃完，又饿了，奇怪", "吃了，还给梦里留了点"],
            .praise: ["哈哈，我就知道我好看", "低调，灯光太晃眼了", "谢谢，签名排队哦", "你也很有眼光嘛"],
            .tease: ["哈哈哈，被你抓包了", "我这叫战略性休息", "笑吧笑吧，快乐最重要", "你笑起来的样子也很好笑"],
            .play: ["冲呀！快乐无敌", "我的主意从来没错过", "走，晚了快乐就跑了", "带上我，气氛组就位"],
            .music: ["我的脚已经在跳了", "这段封神，不接受反驳", "听得我想原地转圈", "好听！再放亿遍"],
        ],
    ]

    // MARK: 反应收尾（每人格 × 每话题 2 句）

    static let closers: [PetPersonality: [PetChatTopic: [String]]] = [
        .cute: [
            .care: ["那就好，我放心啦", "我们都要好好吃饭哦"],
            .praise: ["你最好啦", "嘿嘿，开心一整天"],
            .tease: ["好啦好啦，不逗你了", "下次我陪你一起打哈欠"],
            .play: ["说好啦，不见不散", "我已经开始期待了"],
            .music: ["这首要加入我的最爱", "听完心情都变好了"],
        ],
        .mischievous: [
            .care: ["走，带你去找吃的", "下次藏吃的叫上我"],
            .praise: ["嘿嘿，知道我的厉害了吧", "下次见面继续夸"],
            .tease: ["保密哦，这是我们的秘密", "下次行动，带你一个"],
            .play: ["出发！别掉队哦", "我数三二一就跑"],
            .music: ["这首归我了，谁也别抢", "下次还蹦这一首"],
        ],
        .melancholy: [
            .care: ["嗯……那我也去吃一点", "有你问一句，好多了"],
            .praise: ["嗯……我记住了", "心里，暖暖的"],
            .tease: ["唉……一起蔫着也好", "你陪我，我就没那么困了"],
            .play: ["嗯，慢慢来，不急", "走不动了，就喊我"],
            .music: ["这首听完，我就去睡了", "嗯，陪我听到最后吧"],
        ],
        .grumpy: [
            .care: ["哼，算你有良心", "下次记得带吃的来"],
            .praise: ["哼，知道就好", "别得意，我只是顺眼"],
            .tease: ["哼，不跟你计较", "下次再笑我，我真生气了"],
            .play: ["哼，走吧走吧", "玩完了记得送我回来"],
            .music: ["哼，这首我允许循环", "就冲这首，陪你坐会儿"],
        ],
        .joker: [
            .care: ["干饭小队，集合完毕", "吃饱了才有力气快乐"],
            .praise: ["哈哈，今天是个好日子", "我们俩都闪闪发光"],
            .tease: ["哈哈哈，今天份的快乐达标了", "笑一笑，十年少"],
            .play: ["快乐小分队，出发", "回头见，我去也"],
            .music: ["这首必须单曲循环", "快乐已经溢出来了"],
        ],
    ]
}

// MARK: - 详情页台「等你」库 + 灵动岛「到家」库（(32) 新增）

extension PetLines {

    /// 详情页·等你库（陪伴向；种子三句为 Miller 原话逐字收录）。
    static let stageWaiting = [
        "骗你的，我在这里等你",
        "我还想多陪你一会",
        "今天你辛苦啦",
        "你来啦，我都等半天了",
        "这首我陪你听完",
        "不急，我就在这儿",
        "你不在的时候，我就乖乖等着",
        "听到你的脚步声啦",
        "慢慢听，我哪儿也不去",
        "你回来啦，今天也辛苦了",
    ]

    /// 灵动岛·到家库（调皮向；种子句为 Miller 原话逐字收录）。
    static let islandHome = [
        "没想到吧，这就是我的家",
        "我先一步到家啦",
        "上面风好，我住下了",
        "嘘，别告诉他们我在这儿",
        "我在这儿能看见你听歌",
        "这位置视野最好，我先占了",
        "我在这儿等你们半天了",
        "岛上空气好，适合发呆",
        "别羡慕，我就是到得早",
        "我在这儿给你占座呢",
    ]
}
