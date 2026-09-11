import AppKit
import SwiftUI

/// OhNews 的语义颜色令牌。
///
/// 规则只有一条：**卡片永远比列表亮一档**。层级靠明度差建立，而不是边框、
/// 阴影或嵌套底色，所以同一个语义值在深/浅外观下方向一致。
///
/// `reader.css` 使用同一套语义值（见 `notes/ohnews-ui-tokens.md`），
/// 避免 SwiftUI 界面与 WebView 正文之间出现色温和对比度断层。
enum Palette {
    // MARK: - 表面

    /// 窗口与阅读区底色。
    static let windowBackground = dynamic(dark: 0x101215, light: 0xFFFFFF)
    /// 侧栏底色，与窗口底轻微区分。
    static let sidebarSurface = dynamic(dark: 0x16191E, light: 0xF3F4F6)
    /// 列表背景，比卡片暗一档。
    static let listSurface = dynamic(dark: 0x101215, light: 0xF4F5F7)
    /// 列表行卡片，比列表亮一档。
    static let cardSurface = dynamic(dark: 0x1A1E24, light: 0xFFFFFF)
    /// 行悬浮。
    static let cardHover = dynamic(dark: 0x212630, light: 0xEEF0F3)
    /// 需要「抬起」的表面：提示条、代码块。
    static let raisedSurface = dynamic(dark: 0x20252C, light: 0xF7F8FA)
    /// 极少数确实需要分割线的地方。浅色下用浅灰而非半透明黑，避免依赖叠加计算。
    static let separator = dynamic(dark: 0x262B33, light: 0xE0E3E8)

    // MARK: - 文字

    static let textPrimary = dynamic(dark: 0xF0F2F5, light: 0x16181C)
    static let textSecondary = dynamic(dark: 0xA6ADB8, light: 0x5C636E)
    static let textTertiary = dynamic(dark: 0x767E8A, light: 0x8A919C)

    // MARK: - 强调

    /// 链接与选中。
    static let accent = dynamic(dark: 0x6FA8FF, light: 0x0A63CE)
    /// AI 相关内容的识别色，刻意与 `accent` 区分开。
    static let aiAccent = dynamic(dark: 0x7FD1C1, light: 0x1F8A78)

    // MARK: - 派生

    /// 选中行底色。用强调色低透明度叠加，跟随系统强调色设置。
    static var cardSelected: Color { Color.accentColor.opacity(0.16) }

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

/// 间距与圆角。以 4pt 为基准，避免各视图各写一套数字。
enum Metrics {
    static let rowCornerRadius: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 12
    /// 卡片之间的留白。
    static let cardSpacing: CGFloat = 6
    /// 列表左右留白。
    static let listHorizontalInset: CGFloat = 10

    static let badgeCornerRadius: CGFloat = 6
    static let badgeSize: CGFloat = 16
    static let thumbnailCornerRadius: CGFloat = 8
    static let bannerCornerRadius: CGFloat = 10
    static let tagCornerRadius: CGFloat = 4

    /// AI 摘要左侧识别线的宽度。
    static let summaryRuleWidth: CGFloat = 2
    /// 摘要相对标题的缩进。
    static let summaryIndent: CGFloat = 8
}

/// 字号与行距。集中定义，保证列表各层级的对比关系稳定。
enum Typography {
    static let listTitle = Font.system(size: 15.5, weight: .semibold)
    static let listTitleLineSpacing: CGFloat = 2
    static let summaryTitle = Font.system(size: 13.5, weight: .semibold)
    static let summaryBody = Font.system(size: 13)
    static let summaryBodyLineSpacing: CGFloat = 3
    static let summaryFootnote = Font.system(size: 12)
    static let metadata = Font.system(size: 11.5)
    static let tag = Font.system(size: 11)
}

private extension NSColor {
    /// `RRGGBB`，不透明度由调用方叠加，避免深色值被误判为带 alpha 的浅色值。
    convenience init(rgbHex: UInt32) {
        let red = CGFloat((rgbHex >> 16) & 0xFF) / 255
        let green = CGFloat((rgbHex >> 8) & 0xFF) / 255
        let blue = CGFloat(rgbHex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
