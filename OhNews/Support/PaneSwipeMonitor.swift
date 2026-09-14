// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit

/// 触控板横扫：把一次手势的**累计位移**与**速度**持续报出来，由 `PaneLayout`
/// 按帧写宽度，做到滑多少收多少；松手时再由它用速度投影决定落点。
///
/// ## 为什么监听滚轮事件而不是 `.swipe`
///
/// 这里改正过一次。第一版监听 `NSEvent.EventType.swipe`，实测**完全收不到**：
/// 当系统设置里的「在页面之间轻扫」是**两指**时，两指横扫产生的是带横向增量的
/// **滚轮事件**（`scrollWheel`），WebView 就是靠它做前进/后退的；`.swipe` 事件
/// 只在三指／四指模式下才产生。所以监听 `.swipe` 等于在等一种不会发生的事件。
///
/// ## 为什么要区分 phase 与 momentumPhase
///
/// - `phase` 描述**手指**还在不在板上。手指离开后系统会继续送来一串
///   **惯性**事件（`momentumPhase` 非空），那属于系统自己的甩动。这里把它们挡掉：
///   惯性由应用侧那一次弹簧动画给，两者叠加会变成"收过头"。
/// - 挡惯性事件必须**只挡横向的**：纵向惯性正是列表的滚动惯性，挡掉列表就不滑了。
///
/// ## 为什么结束时返回 nil
///
/// 横向滚动事件被吞掉（不传下去），否则正文里的 `WKWebView` 会顺手做一次前进/后退。
@MainActor
final class PaneSwipeMonitor {
    private var monitor: Any?
    /// 本次手势累计的横向位移，向左为负。
    private var translation: CGFloat = 0
    /// 平滑后的速度（点／秒），向左为负。
    private var velocity: Double = 0
    private var lastTimestamp: TimeInterval?
    private var isTracking = false

    /// - Parameters:
    ///   - onChanged: 每个事件报一次（累计位移, 速度）。
    ///   - onEnded: 手指离开时报一次（累计位移, 速度）。
    func install(
        onChanged: @escaping (CGFloat, Double) -> Void,
        onEnded: @escaping (CGFloat, Double) -> Void
    ) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)

            // 手指离开后的惯性：横向的挡掉（那是应用侧动画的活），纵向的放行
            // （列表的滚动惯性就靠它）。
            if !event.momentumPhase.isEmpty {
                return horizontal ? nil : event
            }

            if event.phase == .began {
                self.translation = 0
                self.velocity = 0
                self.lastTimestamp = nil
                self.isTracking = true
            } else if !self.isTracking, horizontal {
                // 没有 phase 的事件：鼠标横向滚轮，或合成事件（自动测试用）。
                // 当作一次新手势的开始。
                self.translation = 0
                self.velocity = 0
                self.lastTimestamp = nil
                self.isTracking = true
            }

            guard self.isTracking else { return event }

            // 手势进行中夹进纵向滚动：放行，但别把它算进位移。
            guard horizontal else { return event }

            if let last = self.lastTimestamp {
                let dt = max(event.timestamp - last, 0.004)
                let instant = Double(event.scrollingDeltaX) / dt
                // 单次事件的瞬时速度很噪，做一次平滑。
                self.velocity = self.velocity * 0.6 + instant * 0.4
            }
            self.lastTimestamp = event.timestamp
            self.translation += event.scrollingDeltaX

            if event.phase == .ended || event.phase == .cancelled {
                self.isTracking = false
                onEnded(self.translation, self.velocity)
            } else {
                onChanged(self.translation, self.velocity)
            }

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
