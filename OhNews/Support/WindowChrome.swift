// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit

/// 让窗口的内容绘制范围延伸到标题栏之下，并读回那段安全区高度。
///
/// 目的：**让三栏之间的分隔线一直通到窗口最顶端**。默认内容从工具栏下方开始，
/// 两条竖线到工具栏就断了，顶部看起来是一条独立的横带。
///
/// 只做"延伸"是不够的（实测：三栏仍被安全区扣掉 52pt，线到不了顶），所以配套要
/// 把这段高度转成**栏内内容的顶部内边距**——见 `ThreePaneShell` 的 `topInset`：
/// 栏的底色与分隔线铺满到顶，文字仍从工具栏下方开始。
///
/// 从 `task` 里取窗口设属性，而不是做一个 `NSViewRepresentable`：后者会把一个
/// NSView 插进布局链，之前实测会引发窗口尺寸失控。
enum WindowChrome {
    /// 标题栏 + 工具栏占掉的高度。窗口配置完成后才有效。
    static var topSafeAreaInset: CGFloat? {
        guard let inset = NSApp.windows.first(where: { $0.isVisible })?
            .contentView?.safeAreaInsets.top, inset > 0 else { return nil }
        return inset
    }

    static func applyFullSizeContent() {
        for window in NSApp.windows where window.isVisible {
            if window.styleMask.contains(.fullSizeContentView) == false {
                window.styleMask.insert(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = true
            // 工具栏底下那条系统分界线横穿三个模块，去掉。
            window.toolbar?.showsBaselineSeparator = false
        }
    }
}
