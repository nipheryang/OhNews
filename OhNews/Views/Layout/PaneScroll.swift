// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import SwiftUI

/// 侧栏与列表栏共用的滚动容器：`ScrollView` + `LazyVStack`，**不带滚动条**。
///
/// ## 为什么不用 `List`
///
/// `List` 底层是 AppKit 的表格视图，它的滚动条只能靠 `.scrollIndicators(.hidden)`
/// 关——而这个修饰器**在 macOS 的 `List` 上不生效**（两种加法都实测过：加在外层
/// 容器上、直接加在 `List` 上，重排后 `hasVerticalScroller` 都会变回 `true`）。
/// 系统「显示滚动条」设为"始终"时那是一条永远挂着的条。
///
/// 之前的对策是在 AppKit 一层反复补扫（尺寸变化时补 + 每秒轮询），代价是：
/// 每次重排到补上之间会**闪一下**，而且 SwiftUI 每次重排都会把它打开——
/// 用键盘上下键选择时尤其明显（每次按键都是一次重排）。
///
/// `ScrollView` 上同一个修饰器是有效的，所以这里从根上不需要补扫。
///
/// ## 代价
///
/// `List` 白送的两样要自己给：
/// 1. **键盘上下选择**（见 `onMoveCommand`，由各栏自己挂）；
/// 2. **行视图复用**——`LazyVStack` 只懒加载、不复用。当前规模（列表有上限、
///    实测文档高约七千点）没有差别；若将来条目到几千行会变慢。
struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
