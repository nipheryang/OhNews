// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import SwiftUI

/// 三栏外壳：工具栏之下、三个各自独立且**高度一致**的栏。
///
/// ## 为什么不用 `NavigationSplitView`
///
/// 它在 macOS 上把侧栏画成**通到窗口最顶端**的一条：侧栏内容伸进标题栏/工具栏
/// 底下，靠一条"安全区"把内容压下来。那条安全区一旦与窗口尺寸对不上，症状就是
/// 侧栏文字跑到最顶端、被工具栏盖住，滚动视图的可视原点也跟着错位——往上滑
/// 也回不到第一行（因为"滚动到 0"已经是它认为的顶部）。这一个 bug 反复修不掉，
/// 根子在它：侧栏与工具栏共用了一块纵向空间，而这块空间的分配不可控。
///
/// 这里改成用户描述的结构：**工具栏是顶部完整的一条横带，三栏在它下面各占自己的
/// 宽度、共享同一个高度**，谁也不与工具栏重叠。
///
/// ## 为什么高度一定是这一条的
///
/// `HSplitView` 是 AppKit 的 `NSSplitView`：它只切分**宽度**，子视图的高度由它自己
/// 的高度强制给足。于是"某一栏按自己的内容长度索取高度"这件事在结构上不可能发生
/// ——列表再多、正文再长，都只能在栏内滚动。
struct ThreePaneShell<SidebarPane: View, ListPane: View, DetailPane: View>: View {
    @Binding var showsSidebar: Bool
    @ViewBuilder var sidebar: () -> SidebarPane
    @ViewBuilder var list: () -> ListPane
    @ViewBuilder var detail: () -> DetailPane

    var body: some View {
        HSplitView {
            if showsSidebar {
                sidebar()
                    .frame(minWidth: 188, idealWidth: 208, maxWidth: 300)
            }

            list()
                // 中栏是扫描区：太窄会把标题挤成三行短词，太宽又让阅读区失去沉浸感。
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 520)

            detail()
                .frame(minWidth: 320, maxWidth: .infinity)
        }
        .toolbar {
            // 侧栏开关。原先由 `NavigationSplitView` 自动提供，换成自绘外壳后
            // 要自己给——放在 `.navigation` 位，位置与系统那个一致。
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
}
