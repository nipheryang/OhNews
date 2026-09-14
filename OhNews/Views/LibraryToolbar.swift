// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import OhNewsKit
import SwiftUI

/// 始终可用的一组工具栏按钮：星标、稍后读、外观、设置。
///
/// ## 为什么搬到正文栏上
///
/// 它们原先声明在**文章列表栏**（`StoryListView`）上，于是收起列表栏时一起消失。
/// 但那几个按钮在全屏读正文时同样有用——收藏、稍后读、设置都属于"正在读这篇文章"
/// 这个场景，不该随着列表栏一起走。
///
/// 只有「重新获取榜单」留在列表栏上：它与列表内容绑定，列表收起时跟着消失，
/// 符合直觉。
struct LibraryToolbar: ToolbarContent {
    let state: AppState
    /// 当前实际是不是深色。由挂载方算好传进来——`ToolbarContent` 里读环境值的
    /// 支持不稳，交给视图算更可靠。
    let isDark: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.selectedChannelID = LibraryEntry.collection.rawValue
            } label: {
                Label("星标", systemImage: LibraryEntry.collection.systemImage)
            }
            .help("查看星标")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.selectedChannelID = LibraryEntry.readLater.rawValue
            } label: {
                Label("稍后读", systemImage: LibraryEntry.readLater.systemImage)
            }
            .help("查看稍后读")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                state.setAppearance(isDark ? .light : .dark)
            } label: {
                Label(actionLabel, systemImage: isDark ? "sun.max" : "moon")
            }
            .help(actionLabel)
        }

        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .help("配置 AI 摘要")
        }
    }

    private var actionLabel: String {
        isDark ? "切换到浅色外观" : "切换到深色外观"
    }
}
