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
    /// 三栏的宽度、可见性与两种拖动（拖分隔线、触控板横扫）共用这一份状态。
    @State private var layout = PaneLayout()
    @State private var swipeMonitor = PaneSwipeMonitor()
    /// 标题栏 + 工具栏的高度，由窗口读回后传给外壳。
    @State private var windowTopInset: CGFloat = 0

    var body: some View {
        ThreePaneShell(
            layout: layout,
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
        // 外壳背后铺**纸色**，与三栏同色。
        //
        // 这里一度铺的是 underPageBackgroundColor（"桌面色"）：那是想让正文卡片的
        // 投影有个落点。但投影落在左邻的列表栏上，根本不需要它；而它比纸略暗，
        // 于是栏位收放的瞬间纸色移开、露出桌面色，就是用户看到的"闪一下变个颜色"。
        // 同色之后，任何瞬间露出来的都还是纸色。
        .background(Palette.paper.ignoresSafeArea())
        // 强调色就是墨色：整套语言是单色的，控件也应如此。
        .tint(Palette.accent)
        .preferredColorScheme(preferredScheme)
        // 先载入源与上次选中的频道；频道确定后由下面这个 task 负责加载内容。
        // 手势监听单独装一次，且排在启动任务之前：启动链路里任何一步卡住
        // （例如钥匙串授权弹窗阻塞主线程）都不该让它装不上——之前就栽在这里。
        .task { installSwipeGesture() }
        .task {
            await state.prepare()
            await applyWindowChrome()
            installSwipeGesture()
            // 侧栏与列表栏不显示滚动条。必须由 AppKit 一层反复施加——
            // 原因见 Scrollbars 的注释（SwiftUI 的 .scrollIndicators 在这些
            // List 上不生效，而且每次重排还会把条装回来）。
            Scrollbars.hideAppSideScrollers()
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
    ///
    /// 这里只做转发：手势识别在 `PaneSwipeMonitor`，收放由 `PaneLayout` 负责——
    /// 手势只发一次指令，连续过程交给它的弹簧动画。
    private func installSwipeGesture() {
        // 手势只发一次指令；收起的连续过程由 `PaneLayout` 的弹簧动画完成。
        swipeMonitor.install { collapsing in
            layout.swipe(collapsing: collapsing)
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
