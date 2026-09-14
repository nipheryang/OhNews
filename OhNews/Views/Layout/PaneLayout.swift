// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

/// 三栏布局唯一的一份状态：宽度、可见性、分隔线拖动、触控板横扫的收放。
///
/// ## 横扫是"一次性触发"，不是"跟手"
///
/// 这里删掉过一版"跟手"实现：手势过程中按帧写宽度，滑多少收多少，松手时用位移加
/// 速度投影落点。那是另一个交互方向，现在不要了。**手势只负责发出一次指令**，
/// 收起的过程交给动画——`settle` 用弹簧把宽度收到 0，收完才把那一栏移出视图树。
///
/// 保留"先动宽度、后翻可见性"这个顺序，是因为它决定了两件事：
/// 1. 收起是**连续**的（宽度一路变小），不是把一栏突然从树里摘掉；
/// 2. 中栏能顺带接住侧栏让出的宽度（见 `listWidth`），界线只移动一条。
@Observable
@MainActor
final class PaneLayout {
    // MARK: - 取值

    static let sidebarRange: ClosedRange<Double> = 180 ... 320
    static let listRange: ClosedRange<Double> = 320 ... 560
    static let defaultSidebarWidth: Double = 208
    static let defaultListWidth: Double = 400

    private let defaults: UserDefaults

    // MARK: - 可见性

    private(set) var showsSidebar = true
    private(set) var showsList = true

    // MARK: - 宽度

    /// 用户设定的宽度（拖分隔线拖出来的），落盘记住。
    private(set) var storedSidebarWidth: Double
    private(set) var storedListWidth: Double
    /// 收放动画过程中的宽度。`nil` 表示没有正在进行动画。
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
    var listWidth: Double {
        guard showsList else { return 0 }
        let own = liveListWidth ?? storedListWidth
        let freed = storedSidebarWidth - sidebarWidth
        // 中栏自己也在从 0 展开时（两栏都收起后往右扫），一开始不能凭空多出
        // 208pt——那是 208pt 的跳变，所以按"露出多少"的比例给。
        let share = storedListWidth > 0 ? min(max(own / storedListWidth, 0), 1) : 0
        return own + freed * share
    }

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

    // MARK: - 触控板横扫：一次性触发

    /// 一次横扫。`collapsing` 为真表示向左扫（收起一栏）。
    func swipe(collapsing: Bool) {
        if collapsing {
            if showsSidebar { setSidebar(visible: false) }
            else if showsList { setList(visible: false) }
        } else {
            if !showsList { setList(visible: true) }
            else if !showsSidebar { setSidebar(visible: true) }
        }
    }

    // MARK: - 工具栏按钮

    func toggleSidebar() {
        setSidebar(visible: !showsSidebar)
    }

    // MARK: - 关节：先动宽度，再翻可见性

    private enum Target { case sidebar, list }

    private func setSidebar(visible: Bool) { set(.sidebar, visible: visible) }
    private func setList(visible: Bool) { set(.list, visible: visible) }

    /// `visible == false`：宽度弹簧收到 0，收完把那一栏移出视图树。
    /// `visible == true`：先让它以 0 宽进树（否则宽度长出来也看不见），再动画长回设定值。
    ///
    /// **进出视图树与翻可见性都放在"无动画事务"里**。这一点是必须的：这两件事本身
    /// 不该有动画（否则会与宽度动画叠加，表现为展开时"咔"地一下直接到位——用户报的
    /// "恢复时没有过渡"就是这个），只有宽度的弹簧是动画。
    private func set(_ target: Target, visible: Bool) {
        // **宽度不参与动画**——这是这一段最关键的决定。
        //
        // 正文栏里是 `WKWebView`，AppKit 视图跟不了 SwiftUI 的逐帧插值：宽度若在
        // 动画中逐帧变化，WebKit 就在几个时刻各重排一次，表现为"先露出一点、再平移
        // 一个工具栏高度、最后突然覆盖"。用户报的就是这个。
        //
        // 改成：布局一步到位（那一栏立刻进出视图树，正文栏立刻拿到最终宽度，只重排
        // 一次），而"滑走"交给 `ThreePaneShell` 里的 `.transition(.move(edge:))`
        // ——过渡会把即将离场的那一栏画在原位再平移出去。于是正文始终不动，
        // 是两栏从它上方滑走，也就是"平移覆盖"。
        withAnimation(Motion.pane) {
            switch target {
            case .sidebar:
                showsSidebar = visible
            case .list:
                showsList = visible
            }
        }
    }

    private func storedWidth(_ target: Target) -> Double {
        switch target {
        case .sidebar: storedSidebarWidth
        case .list: storedListWidth
        }
    }

    private func animateWidth(_ target: Target, to value: Double, completion: @escaping () -> Void) {
        switch target {
        case .sidebar:
            withAnimation(Motion.pane) { liveSidebarWidth = value } completion: { completion() }
        case .list:
            withAnimation(Motion.pane) { liveListWidth = value } completion: { completion() }
        }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
