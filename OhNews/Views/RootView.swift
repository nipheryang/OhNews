// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import OhNewsKit
import SwiftUI

/// 三栏结构：左侧信息源与频道，中间列表，右侧阅读器。
///
/// 结构本身交给 `ThreePaneShell`——工具栏是顶部完整的一条，三栏在它下面各自独立、
/// 高度一致。这里只负责装配状态、外观与加载时机。
struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var showsSidebar = true
    @State private var showsList = true
    @State private var swipeMonitor = PaneSwipeMonitor()
    /// 标题栏 + 工具栏的高度，由窗口读回后传给外壳。
    @State private var windowTopInset: CGFloat = 0

    var body: some View {
        ThreePaneShell(
            showsSidebar: $showsSidebar,
            showsList: $showsList,
            topInset: windowTopInset
        ) {
            SidebarView()
                #if DEBUG
                .paneHeightProbe("侧栏")
                #endif
        } list: {
            StoryListView()
                #if DEBUG
                .paneHeightProbe("中栏")
                #endif
        } detail: {
            StoryDetailView()
                #if DEBUG
                .paneHeightProbe("详情")
                #endif
        }
        // 尺寸下限放在**内容里面**（不放窗口与内容之间）。
        // 放窗口那一层会截断窗口安全区的传递——而安全区正是"工具栏占掉的那一段"，
        // 被截断之后内容就画到工具栏底下。实测对照：放外面时栏高与工具栏之下的
        // 内容区对不上；放里面则一致。
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        // "桌面"底色：比正文那张纸略暗一档，投影才有落点。
        // 正文自己是不透明的 paper 并带投影，于是它读起来浮在另外两栏之上。
        .background(Color(nsColor: .underPageBackgroundColor).ignoresSafeArea())
        // 强调色就是墨色：整套语言是单色的，控件也应如此。
        .tint(Palette.accent)
        .preferredColorScheme(preferredScheme)
        // 先载入源与上次选中的频道；频道确定后由下面这个 task 负责加载内容。
        .task {
            await state.prepare()
            // 滚动条：滑动才出现、停下就隐藏。系统偏好若为"始终"，只有落到
            // AppKit 才能逐视图改（见 ScrollbarStyle）。
            ScrollbarStyle.applyOverlay()
            await applyWindowChrome()
            installSwipeGesture()
        }
        .onChange(of: state.selectedChannelID) { _, _ in
            // 列表会重建，新滚动视图要再设一次。
            ScrollbarStyle.applyOverlay()
        }
        .task(id: state.selectedChannelID) {
            guard let channelID = state.selectedChannelID else { return }
            // 收藏／稍后读不是频道：中栏由收藏列表自己渲染，不去跑频道加载。
            guard LibraryEntry.matching(channelID) == nil else { return }
            await state.loadChannel(channelID)
        }
    }

    /// 触控板横扫：向左依次收起侧栏、中栏；向右反着依次放回来。
    ///
    /// 用本地监听器而不是给某个视图加手势，所以**鼠标在哪个位置都能触发**，
    /// 且不会被正文里的 `WKWebView` 抢走（它默认会拿这个手势做前进／后退）。
    private func installSwipeGesture() {
        swipeMonitor.install { goingLeft in
            if goingLeft {
                if showsSidebar {
                    showsSidebar = false
                } else if showsList {
                    showsList = false
                }
            } else {
                if showsList == false {
                    showsList = true
                } else if showsSidebar == false {
                    showsSidebar = true
                }
            }
        }
    }

    /// 让三栏的分隔线通到窗口顶端：先把内容延伸到标题栏之下，
    /// 再把那段安全区高度读回来交给外壳（作为栏内容的顶部内边距）。
    @MainActor
    private func applyWindowChrome() async {
        WindowChrome.applyFullSizeContent()
        for _ in 0..<20 {
            if let inset = WindowChrome.topSafeAreaInset {
                windowTopInset = inset
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 最小尺寸放这里：既能约束布局，又不截断窗口安全区。
    ///
    /// 定得很低是有意的——窗口变矮时该牺牲的是**下边缘**（三栏整体留在原处，
    /// 最后几条掉出去，列表在栏内自己滚），而不是顶部。这个值只表示"再矮就不像话了"。
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
