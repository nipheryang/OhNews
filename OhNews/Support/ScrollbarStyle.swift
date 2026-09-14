// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit

/// 把窗口里的滚动条统一设成 **overlay** 样式：**滑动时才出现，停下就隐藏**。
///
/// 为什么要落到 AppKit：系统的「显示滚动条」偏好若设成"始终"，SwiftUI 没有 API
/// 能改单个列表。这里遍历每个 `NSScrollView` 单独设样式——**只影响本应用**，
/// 不会写回系统偏好。
///
/// 列表会随频道/栏目切换而重建，所以调用点要覆盖这些时机（见 `RootView`）。
enum ScrollbarStyle {
    /// 连续几次执行：视图是异步建出来的，一次遍历可能还没轮到新列表。
    static func applyOverlay(retries: Int = 4) {
        for attempt in 0..<retries {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.35) {
                applyToAllWindows()
            }
        }
    }

    private static func applyToAllWindows() {
        for window in NSApp.windows {
            guard let root = window.contentView else { continue }
            apply(to: root)
        }
    }

    private static func apply(to view: NSView) {
        if let scroll = view as? NSScrollView, scroll.scrollerStyle != .overlay {
            scroll.scrollerStyle = .overlay
        }
        for sub in view.subviews {
            apply(to: sub)
        }
    }
}
