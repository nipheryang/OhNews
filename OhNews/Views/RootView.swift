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
        } content: {
            StoryListView()
                // 中栏是扫描区，需要足够宽度放下标题与摘要；太窄会把标题挤成
                // 一片三行短词，太宽又会让右侧阅读区失去沉浸感。
                .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 480)
        } detail: {
            StoryDetailView()
        }
        .background(Palette.paper)
        // 强调色就是墨色：整套语言是单色的，控件也应如此。
        // 这同时把侧栏的原生选中高亮从系统蓝改成墨色，省去额外的样式对抗。
        .tint(Palette.accent)
        .preferredColorScheme(preferredScheme)
        // 先载入源与上次选中的频道；频道确定后由下面这个 task 负责加载内容。
        .task { await state.prepare() }
        .task(id: state.selectedChannelID) {
            guard let channelID = state.selectedChannelID else { return }
            await state.loadChannel(channelID)
        }
    }

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
