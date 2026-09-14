// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit

/// 触控板横扫：识别一次手势，报出方向。**不跟手**——手势只发一次指令，
/// 收起的连续过程交给 `PaneLayout` 的动画。
///
/// ## 为什么监听滚轮事件而不是 `.swipe`
///
/// 这里改正过一次。第一版监听 `NSEvent.EventType.swipe`，实测**完全收不到**：
/// 当系统设置里的「在页面之间轻扫」是**两指**时，两指横扫产生的是带横向增量的
/// **滚轮事件**（`scrollWheel`），WebView 就是靠它做前进/后退的；`.swipe` 事件
/// 只在三指／四指模式下才产生。
///
/// ## 为什么要有阈值
///
/// 手指搭在触控板上的一点横向抖动不该被当成"扫了一下"。这里累计一次手势的横向
/// 位移，超过阈值才发指令，并且**一次手势只发一次**。
///
/// ## 为什么结束时返回 nil
///
/// 横向滚动事件被吞掉（不传下去），否则正文里的 `WKWebView` 会顺手做一次前进/后退。
@MainActor
final class PaneSwipeMonitor {
    /// 触发阈值（点）。一次真正的横扫总位移在几百点量级，80 很保守。
    private static let threshold: CGFloat = 80
    /// 两次事件间隔超过这个秒数，就当作新的一次手势。
    /// 需要它是因为合成事件（自动测试）没有 `phase`，只能靠时间间隔切分。
    private static let gestureGap: TimeInterval = 0.35

    private var monitor: Any?
    private var translation: CGFloat = 0
    private var lastTimestamp: TimeInterval?
    private var fired = false

    /// - Parameter onSwipe: `true` 表示手指向左（收起），`false` 表示向右（放回）。
    func install(onSwipe: @escaping (Bool) -> Void) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)

            // 手指离开后的惯性：横向的挡掉（那是应用侧动画的活），纵向的放行
            // （列表的滚动惯性就靠它）。
            if !event.momentumPhase.isEmpty {
                return horizontal ? nil : event
            }

            // 手势边界：系统给了 phase 就用它；合成事件没有 phase，用时间间隔兜底。
            let isNewGesture = event.phase == .began
                || (self.lastTimestamp.map { event.timestamp - $0 > Self.gestureGap } ?? true)
            if isNewGesture {
                self.translation = 0
                self.fired = false
            }
            self.lastTimestamp = event.timestamp

            guard horizontal else { return event }
            guard self.fired == false else { return nil }

            self.translation += event.scrollingDeltaX
            guard abs(self.translation) >= Self.threshold else { return event }

            self.fired = true
            // 正负与系统「自然滚动」设置有关；若方向相反，改这一个比较即可。
            onSwipe(self.translation < 0)
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
