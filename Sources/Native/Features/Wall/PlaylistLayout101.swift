import UIKit

/// (101) 第 1 项：歌单页排版构图定版数值（样板 Space
/// ge-dan-ye-pai-ban-yang-ban 的最终 CSS 即规格蓝本，逐项
/// 对应移植；与原生现状冲突处以样板为准）。
/// - 缝宽：竖屏窄屏（maxW ≤ 520）148；横屏宽屏（minW ≥
///   640）252；其余 clamp(188, 48vw, 330)。原生 120 书脊档
///   为样板未描绘的收起态，保留不动；展开档改走本表。
/// - 内容头：标题 20 粗 / 总数 15。
/// - 网格：2 列（内容宽 ≥ 560 时 3 列）、行距 20 / 列距
///   14、封面圆角 18、卡名 15/600、歌手 13。
/// - 列表行：min 高 72、序号宽 26、缩略图 54 圆角 10、行
///   名 16、歌手 13.5、爱心/加号钮 40。
/// - 拍立得卡：#f4f1ea、圆角 6、内距 8/8/12、奇偶旋转
///   ∓1.1°、封面圆角 3。
/// - 胶囊台：高 88（窄屏 84，已由 MiniBarQuickRowView
///   .expandedBarHeight=84 单源承接）、圆角 高/2、碟 58
///   （窄 46）、歌名 16.5/700、歌手 13.5、控制钮 46 毛玻
///   璃（主钮 54）、进度条左右内缩 26、高 3、填充金
///   #f5c95e、花朵点 17。
/// - 竖屏开缝两行紧凑：左 = 缝宽+8、右 8、高 120、圆角
///   30、碟 36、控制行整行 space-between、内容底距 150。
enum PlaylistLayout101 {

    /// 书脊（收起）档：样板未描绘，原生既有 120 保留。
    static let seamSpineWidth: CGFloat = 120

    /// 展开档缝宽（样板 .app{--seam} 媒体查询三档）。
    static func seamExpandedWidth(viewWidth: CGFloat,
                                  viewHeight: CGFloat) -> CGFloat {
        if viewWidth <= 520, viewHeight >= viewWidth {
            return 148
        }
        if viewWidth >= 640 {
            return 252
        }
        return min(330, max(188, viewWidth * 0.48))
    }

    /// 内容头字号。
    static let contentTitleFont: CGFloat = 20
    static let contentCountFont: CGFloat = 15

    /// 网格。
    static let gridRowGap: CGFloat = 20
    static let gridColumnGap: CGFloat = 14
    static let gridCoverCorner: CGFloat = 18
    static func gridColumns(contentWidth: CGFloat) -> Int {
        contentWidth >= 560 ? 3 : 2
    }

    /// 列表行。
    static let listRowMinHeight: CGFloat = 72
    static let listIndexWidth: CGFloat = 26
    static let listThumbSize: CGFloat = 54
    static let listThumbCorner: CGFloat = 10

    /// 拍立得卡。
    static let polaroidPaper = UIColor(red: 0xF4 / 255, green: 0xF1 / 255,
                                       blue: 0xEA / 255, alpha: 1)
    static let polaroidCorner: CGFloat = 6
    static let polaroidCoverCorner: CGFloat = 3
    static let polaroidTiltDegrees: CGFloat = 1.1

    /// 胶囊台进度填充金（样板 .fill 渐变起色）。
    static let progressGold = UIColor(red: 0xF5 / 255, green: 0xC9 / 255,
                                      blue: 0x5E / 255, alpha: 1)

    /// 竖屏开缝两行紧凑排布是否成立（样板 body.seam-open
    /// 且竖屏媒体查询）。
    static func capsuleTwoRowActive(viewWidth: CGFloat,
                                    viewHeight: CGFloat,
                                    seamExpanded: Bool) -> Bool {
        seamExpanded && viewWidth <= 520 && viewHeight >= viewWidth
    }
    static let capsuleTwoRowHeight: CGFloat = 120
    static let capsuleTwoRowCorner: CGFloat = 30
    static let capsuleTwoRowCoverSize: CGFloat = 36
    static let capsuleTwoRowContentBottom: CGFloat = 150
    /// 两行排：上行（封面/歌名）中心偏移、下行（控制钮整
    /// 行）中心偏移（相对台中心）。
    static let capsuleRowTopOffset: CGFloat = -27
    static let capsuleRowBottomOffset: CGFloat = 25
}
