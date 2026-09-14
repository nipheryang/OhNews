// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct OhNewsApp: App {
    @State private var state = AppState()

    init() {
        // 让本应用的滚动条走 **overlay** 样式：**不滚动就不绘制**，因此不存在常驻滚动条。
        //
        // 这是"侧栏与文章列表栏没有滚动条、且不闪"的解法，而且它必须是**应用级**的：
        // 写进本应用自己的偏好域，**不动系统的「显示滚动条」**。
        //
        // 为什么非要它：SwiftUI 每次重排都会把滚动条重新打开（`hasVerticalScroller`
        // 变回 true），这一点不受我们控制。legacy 样式下"条存在"就等于"画出来"——
        // 用户看到的"闪一下"就是这么来的，靠事后补扫只能把时长压短，压不到零。
        // overlay 样式下条不滚动就不画，于是即使被重新打开也看不见。
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                // 最小高度定得很低，因为窗口变矮时该牺牲的是**下半部分**，
                // 不是上半部分：侧栏的功能入口、列表最前面几条，要一直留在
                // 窗口顶部不动。真正决定这件事的是三列各自的
                // `.containerRelativeFrame(.vertical)`——列高跟着窗口走，
                // 列表在列内自己滚，所以顶部永远稳。
                //
                // 这里的值只是"再矮就不像话了"的下限，不是布局撑不住的下限：
                // 它通过 `.windowResizability(.contentMinSize)` 成为窗口的最小值，
                // 低于它就拉不动了，于是永远到不了溢出那一步。
                // 约束不放在这里：根上的 .frame 会吃掉窗口安全区的一条
                // （安全区 = 工具栏占掉的那段），三栏于是画到工具栏底下。
                // 改由 RootView 内部约束——见其中注释。
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
        // 不再需要 `SidebarCommands()`：它驱动的是 `NavigationSplitView` 的侧栏显隐，
        // 而侧栏现在由 `ThreePaneShell` 自己管，开关是工具栏上那个按钮。

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
