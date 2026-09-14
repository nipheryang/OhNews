// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// 线的粗细与抓取热区的宽度分开：线要细（1pt，对齐设计里的发丝线），
/// 但 1pt 宽的抓取区没人点得中，所以另给 11pt 的透明热区。
/// 放在类型外面：泛型类型不支持静态存储属性。
private let paneSeparatorLineWidth: CGFloat = 1
private let paneSeparatorHitWidth: CGFloat = 11

/// 三栏外壳：工具栏之下，三个各自独立的栏。
///
/// ## 为什么不用 `NavigationSplitView` / `HSplitView`
///
/// - `NavigationSplitView` 会把侧栏画成**通到窗口最顶端**的一条，靠一条安全区把内容
///   压下来。那条安全区与窗口对不上时，侧栏文字就跑到最顶上、滚动原点变成负数，
///   第一行再也回不来。
/// - `HSplitView` 解决了高度，但**宽度不归我们管**：栏宽由 AppKit 记，子视图一重建
///   （切频道、切栏目、跳转正文都会重建）就按声明里的 `idealWidth` 复位——表现就是
///   "调窄之后一点文章，列表栏又弹回那个固定宽度"。分隔线也是 AppKit 画的，改不了
///   样式（深色下几乎看不见）。
///
/// 所以这里全部自己来：**宽度由本视图持有并写进 UserDefaults**（调过就一直记得，
/// 重启也记得），分隔线自己画（深浅两套颜色），正文自己做成悬浮的一张纸。
struct ThreePaneShell<SidebarPane: View, ListPane: View, DetailPane: View>: View {
    @Binding var showsSidebar: Bool
    /// 中栏与侧栏一样可以被收起——触控板横扫手势要依次收起这两栏。
    @Binding var showsList: Bool
    /// 标题栏 + 工具栏占掉的高度。外壳整体铺到窗口顶端（分隔线才通到顶），
    /// 而每一栏的**内容**下移这一段，文字不会钻到交通灯底下。
    let topInset: CGFloat

    @AppStorage("layout.sidebarWidth") private var storedSidebarWidth: Double = 208
    @AppStorage("layout.listWidth") private var storedListWidth: Double = 400

    /// 拖动过程中的宽度只放在内存里。
    ///
    /// 之前是每拖一帧都写 `@AppStorage`，于是一帧里发生：写 UserDefaults →
    /// 触发一次布局 → 再读回新值。手指还在动，值已经在往回弹，表现就是剧烈抖动。
    /// 现在拖动期间只改这两个 `@State`，**松手时才落盘一次**。
    @State private var liveSidebarWidth: Double?
    @State private var liveListWidth: Double?

    private var sidebarWidth: Double { liveSidebarWidth ?? storedSidebarWidth }
    private var listWidth: Double { liveListWidth ?? storedListWidth }

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragBase: (sidebar: Double, list: Double)?

    @ViewBuilder var sidebar: () -> SidebarPane
    @ViewBuilder var list: () -> ListPane
    @ViewBuilder var detail: () -> DetailPane

    private enum Handle { case sidebar, list }

    private static var sidebarRange: ClosedRange<Double> { 180 ... 320 }
    private static var listRange: ClosedRange<Double> { 320 ... 560 }

    var body: some View {
        HStack(spacing: 0) {
            if showsSidebar {
                sidebar()
                    .frame(width: sidebarWidth)
                    // 先给内容让出工具栏那一段，再铺底色——底色因此铺满到窗口顶端，
                    // 而列表从工具栏下方开始。
                    .padding(.top, topInset)
                    .background(Palette.paper)
                separator(.sidebar)
            }

            if showsList {
                list()
                    .frame(width: listWidth)
                    .padding(.top, topInset)
                    .background(Palette.paper)

                // 列表与正文之间**不画线**：正文是浮起来的一张纸，它的边缘与投影
                // 本身就是分界，再叠一条线反而是两套语言。但拖拽热区保留。
                separator(.list, drawsLine: false)
            }

            detailPane
        }
        // 外壳铺到窗口最顶端：分隔线要贯穿标题栏那一条。
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            // 侧栏开关。原先由 `NavigationSplitView` 自动提供，自绘外壳后要自己给。
            ToolbarItem(placement: .navigation) {
                Button {
                    showsSidebar.toggle()
                } label: {
                    Label("侧栏", systemImage: "sidebar.left")
                }
                .help(showsSidebar ? "隐藏侧栏" : "显示侧栏")
            }
        }
    }

    // MARK: - 正文：浮起来的一张纸

    /// 正文与左侧两栏**不在同一平面**，但只在**与列表交界的那一处**表现出来。
    ///
    /// 一开始我在四周都留了白，结果它像被单独裁出来的一块：上、右、下三条边都与
    /// 窗口分家。这是错的——**只有交界处该有高度感**，其余三边要与窗口融为一体。
    /// 所以现在不留白、不圆角，只留一层**向左投的阴影**：它落在列表栏上，
    /// 读起来就是"正文这张纸压在左边两栏之上"。
    private var detailPane: some View {
        detail()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, topInset)
            .background(Palette.paper)
            // 只在**左侧**圆角：右侧、下方要与窗口融为一体，圆角只出现在和列表
            // 交界的那一对角上，弧度比默认大一些。
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.5 : 0.16),
                radius: 10,
                x: -3,
                y: 0
            )
    }

    // MARK: - 分隔与拖动

    private func separator(_ handle: Handle, drawsLine: Bool = true) -> some View {
        Rectangle()
            .fill(drawsLine ? separatorColor : Color.clear)
            .frame(width: paneSeparatorLineWidth)
            .overlay {
                Color.clear
                    .frame(width: paneSeparatorHitWidth)
                    .contentShape(Rectangle())
                    .gesture(resize(handle))
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
    }

    /// 深浅两套。深色下用**亮**线：纯黑的线上加黑底几乎等于没有，
    /// 这是用户报的第一个问题。
    private var separatorColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.10)
    }

    private func resize(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // 以按下那一刻的宽度为基准，避免逐帧累加造成抖动。
                let base = dragBase ?? (sidebar: sidebarWidth, list: listWidth)
                if dragBase == nil { dragBase = base }
                let delta = value.translation.width

                switch handle {
                case .sidebar:
                    liveSidebarWidth = clamp(base.sidebar + delta, to: Self.sidebarRange)
                case .list:
                    liveListWidth = clamp(base.list + delta, to: Self.listRange)
                }
            }
            .onEnded { _ in
                // 松手才落盘；清掉内存值，之后仍以存储值为准。
                if let live = liveSidebarWidth { storedSidebarWidth = live; liveSidebarWidth = nil }
                if let live = liveListWidth { storedListWidth = live; liveListWidth = nil }
                dragBase = nil
            }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
