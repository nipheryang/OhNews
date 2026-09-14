// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// 三栏布局唯一的一份状态：宽度、可见性、分隔线拖动、触控板横扫的收放。
///
/// ## 为什么单独抽出来
///
/// 拖动分隔线的手势在 `ThreePaneShell` 里，触控板横扫的手势在 `RootView` 里，
/// 两边都要写同一组宽度。宽度只要放在任何一方的 `@State` 里，另一方就够不着——
/// 而"跟手"要求的恰恰是手势过程中**每一帧**都在写宽度。
///
/// ## 跟手与惯性
///
/// 手势不是"过阈值就切换"，而是**拖动**：`dragSwipe` 每来一个事件就按累计位移写
/// 一次宽度（向左扫 → 宽度变小 → 那一栏跟着手指退出去）；松手时 `endSwipe` 用
/// **位移 + 速度**投影出落点，再交给弹簧动画收尾——"干脆地滑一下也能顺势收完"
/// 就是这么来的。
@Observable
@MainActor
final class PaneLayout {
    // MARK: - 取值

    static let sidebarRange: ClosedRange<Double> = 180 ... 320
    static let listRange: ClosedRange<Double> = 320 ... 560
    static let defaultSidebarWidth: Double = 208
    static let defaultListWidth: Double = 400

    /// 手势方向未明朗前不动作的距离（点）：刚碰到触控板那几下抖动没有意义。
    private static let directionLockDistance: CGFloat = 6
    /// 松手时把速度折算成位移的时间窗（秒）——"甩一下"能顺势收完就靠它。
    private static let flingProjection: Double = 0.14

    private enum SwipeTarget { case sidebar, list }

    private let defaults: UserDefaults

    // MARK: - 可见性

    private(set) var showsSidebar = true
    private(set) var showsList = true

    // MARK: - 宽度

    /// 用户设定的宽度（拖分隔线拖出来的），落盘记住。
    private(set) var storedSidebarWidth: Double
    private(set) var storedListWidth: Double
    /// 手势过程中的临时宽度。`nil` 表示没有正在进行的手势。
    private(set) var liveSidebarWidth: Double?
    private(set) var liveListWidth: Double?

    /// 侧栏此刻实际占的宽度（隐藏时是 0）。
    var sidebarWidth: Double {
        showsSidebar ? (liveSidebarWidth ?? storedSidebarWidth) : 0
    }

    /// 中栏此刻实际的宽度。
    ///
    /// **侧栏让出来的那一块归中栏**，而不是让它落到正文上。三栏里只有正文是
    /// `maxWidth: .infinity`（吃掉剩余空间），所以什么都不做的话，侧栏一收，
    /// 往左长的是正文——那就成了"正文把中栏吃掉"。把侧栏腾出的宽度补给中栏之后，
    /// 收放过程中移动的界线就只有侧栏与中栏之间那一条，正文纹丝不动。
    ///
    /// 补给量按**中栏露出多少的比例**给：中栏自己也在从 0 展开时（两栏都收起后
    /// 往右扫），一开始不能凭空多出 208pt——那是 208pt 的跳变。
    var listWidth: Double {
        guard showsList else { return 0 }
        let own = liveListWidth ?? storedListWidth
        let freed = storedSidebarWidth - sidebarWidth
        let share = storedListWidth > 0 ? min(max(own / storedListWidth, 0), 1) : 0
        return own + freed * share
    }

    // MARK: - 手势过程中的状态

    private var swipeTarget: SwipeTarget?
    /// 手势开始时那一栏的宽度，位移以它为基准。
    private var swipeBase: Double = 0
    /// 锁定方向那一刻的累计位移，之后的位移都相对它算。
    private var swipeOrigin: CGFloat = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedSidebarWidth = defaults.object(forKey: Keys.sidebarWidth) as? Double
            ?? Self.defaultSidebarWidth
        storedListWidth = defaults.object(forKey: Keys.listWidth) as? Double
            ?? Self.defaultListWidth
    }

    private enum Keys {
        static let sidebarWidth = "layout.sidebarWidth"
        static let listWidth = "layout.listWidth"
    }

    // MARK: - 分隔线拖动

    func beginDividerDrag() {
        // 基准宽度在按下那一刻固定，避免逐帧累加导致抖动。
        dividerBase = (sidebarWidth, liveListWidth ?? storedListWidth)
    }

    private var dividerBase: (sidebar: Double, list: Double)?

    func dragDivider(_ handle: DividerHandle, translation: CGFloat) {
        guard let base = dividerBase else { return }
        let delta = Double(translation)
        switch handle {
        case .sidebar:
            liveSidebarWidth = clamp(base.sidebar + delta, to: Self.sidebarRange)
        case .list:
            liveListWidth = clamp(base.list + delta, to: Self.listRange)
        }
    }

    /// 松手才落盘。拖动期间只改内存值——每帧写 `UserDefaults` 会触发一次布局、
    /// 再把值读回来，手指还在动值已经在回弹，表现就是剧烈抖动。
    func endDividerDrag() {
        if let live = liveSidebarWidth {
            storedSidebarWidth = live
            defaults.set(storedSidebarWidth, forKey: Keys.sidebarWidth)
            liveSidebarWidth = nil
        }
        if let live = liveListWidth {
            storedListWidth = live
            defaults.set(storedListWidth, forKey: Keys.listWidth)
            liveListWidth = nil
        }
        dividerBase = nil
    }

    enum DividerHandle { case sidebar, list }

    // MARK: - 触控板横扫：跟手

    /// 手势推进。`translation` 是本次手势累计的横向位移（向左为负）。
    func dragSwipe(translation: CGFloat) {
        if swipeTarget == nil {
            guard abs(translation) > Self.directionLockDistance else { return }
            lockSwipe(at: translation)
        }
        guard let target = swipeTarget else { return }
        let delta = Double(translation - swipeOrigin)

        switch target {
        case .sidebar:
            liveSidebarWidth = clamp(swipeBase + delta, to: 0 ... storedSidebarWidth)
        case .list:
            liveListWidth = clamp(swipeBase + delta, to: 0 ... storedListWidth)
        }
    }

    /// 松手。`velocity` 单位是"点／秒"，向左为负。
    func endSwipe(translation: CGFloat, velocity: Double) {
        guard let target = swipeTarget else { return }
        swipeTarget = nil

        let projected = swipeBase + Double(translation - swipeOrigin)
            + velocity * Self.flingProjection

        switch target {
        case .sidebar:
            settle(.sidebar, closed: projected < storedSidebarWidth / 2)
        case .list:
            settle(.list, closed: projected < storedListWidth / 2)
        }
    }

    /// 方向锁定：决定这一次手势动哪一栏，并记下基准宽度。
    private func lockSwipe(at translation: CGFloat) {
        let collapsing = translation < 0

        if collapsing {
            // 收起顺序：先侧栏，再中栏。
            if showsSidebar {
                swipeTarget = .sidebar
                swipeBase = liveSidebarWidth ?? storedSidebarWidth
            } else if showsList {
                swipeTarget = .list
                swipeBase = liveListWidth ?? storedListWidth
            }
        } else {
            // 放回来的顺序与收起相反：先中栏，再侧栏。
            if !showsList {
                // 先进视图树，否则宽度长出来也看不见。
                showsList = true
                liveListWidth = 0
                swipeTarget = .list
                swipeBase = 0
            } else if !showsSidebar {
                showsSidebar = true
                liveSidebarWidth = 0
                swipeTarget = .sidebar
                swipeBase = 0
            }
        }

        if swipeTarget != nil { swipeOrigin = translation }
    }

    /// 弹簧收尾。`closed` 为真表示收到 0（那一栏隐藏）。
    private func settle(_ target: SwipeTarget, closed: Bool) {
        let finish: () -> Void = { [weak self] in
            guard let self, self.swipeTarget == nil else { return }  // 新手势已开始，别插手
            switch target {
            case .sidebar:
                self.liveSidebarWidth = nil
                self.showsSidebar = !closed
            case .list:
                self.liveListWidth = nil
                self.showsList = !closed
            }
        }

        switch target {
        case .sidebar:
            withAnimation(Motion.pane) {
                liveSidebarWidth = closed ? 0 : storedSidebarWidth
            } completion: { finish() }
        case .list:
            withAnimation(Motion.pane) {
                liveListWidth = closed ? 0 : storedListWidth
            } completion: { finish() }
        }
    }

    // MARK: - 工具栏按钮

    func toggleSidebar() {
        if showsSidebar {
            settle(.sidebar, closed: true)
        } else {
            // 先让它以 0 宽进树，再动画长出来，和手势是同一套路径。
            showsSidebar = true
            liveSidebarWidth = 0
            settle(.sidebar, closed: false)
        }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
