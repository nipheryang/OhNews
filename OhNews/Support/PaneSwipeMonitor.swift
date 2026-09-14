// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit

/// 触控板横扫手势：快速收起／展开边栏。
///
/// 用 `NSEvent` 的**本地监听器**（`addLocalMonitorForEvents`），它在事件分发之前
/// 就拿到事件，这一点是两个需求的来源：
/// - **全局**：鼠标在哪一栏都无所谓，不是"把某个视图做成可滑动的"；
/// - **不被抢**：正文那层 `WKWebView` 本来会把手势拿去做前进／后退，截在它前面就没这问题。
///
/// 依赖系统设置里的「在页面之间轻扫」：设成两指、三指或四指都会产生 `.swipe` 事件；
/// 若该项被关掉，系统根本不产生这类事件，应用无法绕过——这是系统层面的开关。
@MainActor
final class PaneSwipeMonitor {
    private var monitor: Any?

    /// - Parameter onSwipe: `true` 表示手指向左划（收起），`false` 表示向右划（展开）。
    func install(onSwipe: @escaping (Bool) -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe]) { event in
            // 只认横向：纵向轻扫是别的系统手势，不该被这里吃掉。
            guard abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 else {
                return event
            }
            onSwipe(event.deltaX > 0)
            // 吞掉事件：否则 WebView 收到之后会顺手做一次前进／后退。
            return nil
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
