// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct OhNewsApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .defaultSize(width: 1240, height: 780)
        // 让窗口真的照根视图的最小尺寸来。
        //
        // 根视图上的 `.frame(minWidth:minHeight:)` 只是把"内容"做成那个尺寸，
        // **不会**阻止窗口继续缩小。窗口缩到 640 以下时，内容比窗口高，
        // 整块上下溢出，顶部被推到标题栏底下，而它不是滚动视图，滑也滑不回来——
        // 侧栏前几行因此被交通灯盖住，且无法通过滚动找回。
        //
        // `.contentMinSize` 把根视图的最小尺寸交给窗口，用户从此拉不到那个状态。
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
