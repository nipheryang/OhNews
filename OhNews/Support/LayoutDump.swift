// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

#if DEBUG
import AppKit
import SwiftUI

/// 只在 DEBUG 下存在：把窗口里的滚动视图与相关几何打成一行行数字。
///
/// 为什么需要它：侧栏的症状是"滚动位置为 0 时，显示的却是内容的**后半段**"
/// ——说明可视原点本身是错的。而"可视原点错"这件事，只有把 NSScrollView 的
/// frame／可视矩形／内容尺寸／内缩四组数字摆在一起才能定位，猜不出来。
enum LayoutDump {
    static func log(_ tag: String) {
        // 与 `PaneHeightProbe` 同一个坑：应用不在最前时 keyWindow 是 nil，
        // 这里会静默返回，诊断看起来“没触发”，其实是没取到窗口。
        guard let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible }),
              let root = window.contentView else { return }

        let layout = window.contentLayoutRect
        let safeTop = root.safeAreaInsets.top
        NSLog("%@", "[布局诊断/\(tag)] 窗口 contentLayoutRect=\(fmt(layout)) 内容视图=\(fmt(root.frame)) safeAreaTop=\(f(safeTop))")

        var index = 0
        walk(root, window: window, index: &index)
    }

    private static func walk(_ view: NSView, window: NSWindow, index: inout Int) {
        if let scroll = view as? NSScrollView {
            index += 1
            // 换算到窗口坐标：frame 是父视图坐标，直接看会误判层级。
            let inWindow = scroll.convert(scroll.bounds, to: nil)
            let visible = scroll.documentVisibleRect
            let document = scroll.documentView?.frame ?? .zero
            let insets = scroll.contentInsets
            NSLog(
                "%@",
                "[布局诊断]  滚动视图#\(index) 于窗口=\(fmt(inWindow)) 可视矩形=\(fmt(visible)) "
                + "文档=\(fmt(document)) 内缩上=\(f(insets.top)) 下=\(f(insets.bottom)) "
                + "自动内缩=\(scroll.automaticallyAdjustsContentInsets) "
                + "竖条=\(scroll.hasVerticalScroller) 样式=\(scroll.scrollerStyle == .overlay ? "overlay" : "legacy")"
            )
        }
        for sub in view.subviews {
            walk(sub, window: window, index: &index)
        }
    }

    private static func fmt(_ rect: CGRect) -> String {
        "(x=\(f(rect.minX)) y=\(f(rect.minY)) w=\(f(rect.width)) h=\(f(rect.height)))"
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
#endif
