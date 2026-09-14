// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 三栏结构：左侧信息源与频道，中间列表，右侧阅读器。
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                #if DEBUG
                .paneHeightProbe("侧栏")
                #endif
        } content: {
            StoryListView()
                // 中栏是扫描区，需要足够宽度放下标题与摘要；太窄会把标题挤成
                // 一片三行短词，太宽又会让右侧阅读区失去沉浸感。
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
                #if DEBUG
                .paneHeightProbe("中栏")
                #endif
        } detail: {
            StoryDetailView()
                #if DEBUG
                .paneHeightProbe("详情")
                #endif
        }
        // 布局的尺寸约束**放在内容里面**，不放窗口与内容之间。
        //
        // 实测两件事：根上放 `.frame` 会让三栏比"工具栏之下的内容区"高出 17pt
        // （被工具栏盖住）；而完全不约束，布局会发散（栏高涨到 12 万，窗口被报成
        // 五位数）——说明树里有视图在提议无限尺寸。
        // 放在这里两头都满足：约束仍在（不发散），窗口到内容的链路却是干净的。
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .background(Palette.paper)
        // 强调色就是墨色：整套语言是单色的，控件也应如此。
        // 这同时把侧栏的原生选中高亮从系统蓝改成墨色，省去额外的样式对抗。
        .tint(Palette.accent)
        .preferredColorScheme(preferredScheme)
        // 先载入源与上次选中的频道；频道确定后由下面这个 task 负责加载内容。
        .task { await state.prepare() }
        .task(id: state.selectedChannelID) {
            guard let channelID = state.selectedChannelID else { return }
            // 收藏／稍后读不是频道：中栏由收藏列表自己渲染，不去跑频道加载。
            guard LibraryEntry.matching(channelID) == nil else { return }
            await state.loadChannel(channelID)
        }
    }

    /// 最小尺寸放这里：既能约束布局，又不截断窗口安全区。
    private static let minimumWidth: CGFloat = 1000
    private static let minimumHeight: CGFloat = 360

    /// `nil` 表示跟随系统。
    private var preferredScheme: ColorScheme? {
        switch state.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .frame(width: 1240, height: 780)
}
