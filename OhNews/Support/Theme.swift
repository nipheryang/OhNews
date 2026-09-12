// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// OhNews 的语义令牌。
///
/// 取值直接对齐 `nipher-blog-v2/src/styles/global.css` 的设计系统，风格是
/// 极简杂志编辑风：**纯纸白底 + 墨黑文字 + 发丝分割线 + 衬线标题 + 大量留白**。
///
/// 三条必须记住的规则：
///
/// 1. **强调色就是墨色本身**（`accent` == `ink`）。这套语言是单色的，
///    不存在第二配色；需要区分内容时用排版（衬线／等宽、字重、字号），不用颜色。
/// 2. **条目之间用 1px 发丝线分隔，不用卡片底色**。层级来自线条与留白，
///    不是来自明度分层——这与「卡片比列表亮一档」是互斥的两种做法。
/// 3. 元信息一律**等宽 + 大写 + 宽字距**（博客里的 `.eyebrow`），
///    标题一律**衬线**。
///
/// `reader.css` 使用同一套语义值，改一处必须同步另一处。
enum Palette {
    /// 页面底色（博客 `--paper`）。
    static let paper = dynamic(dark: 0x030712, light: 0xFFFFFF)
    /// 抬起表面：代码块、提示条（博客 `--surface`）。
    static let surface = dynamic(dark: 0x111827, light: 0xFFFFFF)

    /// 主文字（博客 `--ink`）。
    static let ink = dynamic(dark: 0xF3F4F6, light: 0x111827)
    /// 次级文字（博客 `--ink-soft`）。
    static let inkSoft = dynamic(dark: 0x9CA3AF, light: 0x4B5563)
    /// 弱化文字（博客 `--ink-faint`）。
    static let inkFaint = dynamic(dark: 0x6B7280, light: 0x9CA3AF)

    /// 分割线（博客 `--line`）。
    static let line = dynamic(dark: 0x1F2937, light: 0xE5E7EB)
    /// 强调线／横线（博客 `--line-strong`）。
    static let lineStrong = dynamic(dark: 0x374151, light: 0xD1D5DB)

    /// 强调色。与 `ink` 同值，这是单色语言的刻意选择。
    static let accent = dynamic(dark: 0xF3F4F6, light: 0x111827)
    /// 强调色之上的文字（博客 `--accent-ink`）。
    static let accentInk = dynamic(dark: 0x030712, light: 0xFFFFFF)

    /// 行悬浮：墨色 3% 薄雾（博客 `color-mix(in srgb, var(--ink) 3%, transparent)`）。
    static var hoverWash: Color { ink.opacity(0.03) }
    /// 选中：同一条墨色薄雾加深到 6%。
    static var selectedWash: Color { ink.opacity(0.06) }
    /// 行内 code 底色（博客 `color-mix(in srgb, var(--ink) 7%, transparent)`）。
    static var codeWash: Color { ink.opacity(0.07) }

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgbHex: isDark ? dark : light)
        })
    }
}

/// 间距与尺寸。对齐博客的尺度感：窄栏 + 充足留白。
enum Metrics {
    /// 列表左右留白（博客 `--gutter` 的下限）。
    static let gutter: CGFloat = 20
    /// 条目内边距（博客 `.post-link` 是 28px 4px，桌面端收紧一些）。
    static let rowVerticalPadding: CGFloat = 18
    static let rowHorizontalPadding: CGFloat = 4

    /// 发丝线宽度。
    static let hairline: CGFloat = 1

    static let radiusSmall: CGFloat = 4
    static let radiusMedium: CGFloat = 10

    /// 眉标字距（博客 `.eyebrow` 是 0.18em）。
    static let eyebrowTracking: CGFloat = 1.6
    /// 元信息字距（博客 `.post-no` 是 0.15em）。
    static let metaTracking: CGFloat = 1.2

    /// AI 区块的左侧引线宽度与缩进（对齐博客 `blockquote` 的 3px）。
    static let quoteRuleWidth: CGFloat = 3
    static let quoteIndent: CGFloat = 12

    /// 正文阅读宽度（博客 `--maxw` 是 720px）。
    static let readerMaxWidth: CGFloat = 720
}

/// 排版。衬线用于标题，等宽用于元信息，系统无衬线用于正文与界面文字。
enum Typography {
    // MARK: - 衬线（标题）

    static let rowTitle = Font.system(size: 17, weight: .semibold, design: .serif)
    static let rowTitleLineSpacing: CGFloat = 3
    static let summaryTitle = Font.system(size: 15, weight: .semibold, design: .serif)
    static let summaryBody = Font.system(size: 13.5, design: .serif)
    static let summaryBodyLineSpacing: CGFloat = 4
    static let readerTitle = Font.system(size: 26, weight: .semibold, design: .serif)
    static let readerTitleLineSpacing: CGFloat = 2
    static let displayTitle = Font.system(size: 20, weight: .semibold, design: .serif)

    // MARK: - 等宽（眉标与元信息）

    static let eyebrow = Font.system(size: 10.5, design: .monospaced)
    static let meta = Font.system(size: 11, design: .monospaced)
    static let readerMeta = Font.system(size: 11.5, design: .monospaced)

    // MARK: - 系统无衬线（界面文字）

    static let ui = Font.system(size: 13)
    static let uiSmall = Font.system(size: 11.5)
    static let emptyStateTitle = Font.system(size: 17, weight: .semibold, design: .serif)
}

/// 动效。缓动曲线直接沿用博客的 `cubic-bezier(0.22, 1, 0.36, 1)`，时长 0.18s。
enum Motion {
    static let standard = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)
    /// 局部浮现（博客的 reveal 是 0.7s，桌面端反应要快得多）。
    static let insert = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)
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
