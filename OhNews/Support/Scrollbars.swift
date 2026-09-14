// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import WebKit

/// 关掉**应用自己的**滚动条（侧栏与列表栏），保留网页里的。
///
/// ## 为什么不是 `.scrollIndicators(.hidden)`
///
/// 实测无效，而且**两种加法都试过**：加在外层容器上、直接加在 `List` 上。
/// 结果是每次窗口重排之后 `NSScrollView.hasVerticalScroller` 又变回 `true`
/// （系统「显示滚动条」偏好为"始终"时样式是 `legacy`，条就一直挂着）。
/// 也就是说 SwiftUI 在这个平台上并不把该修饰器落到 `List` 的滚动视图上。
///
/// ## 为什么要反复施加
///
/// 正因为 SwiftUI 会在布局时把它打开，这里不能只做一次。挂在
/// **窗口尺寸变化**与**内容装载完成**这两个时机上，另加一个轻量轮询兜底——
/// 每 1 秒扫一遍，发现谁又被打开了就关掉。属性赋值本身很廉价，
/// 而且只在"确实被打开"时才写。
///
/// ## 为什么跳过网页视图
///
/// 正文与 AI 解读面板都在 `WKWebView` 里，它们的滚动条属于网页，应保持系统
/// 的 overlay 行为（滑动时才出现）。所以沿父视图往上找，祖先是 `WKWebView` 就跳过。
@MainActor
enum Scrollbars {
    private static var timer: Timer?

    /// 立即扫一遍，并开始轮询。
    static func hideAppSideScrollers() {
        applyToAllWindows()

        // 窗口尺寸一变就立刻补一次：实测 SwiftUI 在重排时会把列表的滚动视图
        // 整个换掉（我设的标志随旧实例一起消失），等轮询那一秒里条会露出来。
        if resizeObserver == nil {
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in applyToAllWindows() }
            }
        }

        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in applyToAllWindows() }
        }
    }

    private static var resizeObserver: NSObjectProtocol?

    private static func applyToAllWindows() {
        for window in NSApp.windows {
            guard let root = window.contentView else { continue }
            apply(to: root)
        }
    }

    private static func apply(to view: NSView) {
        if let scroll = view as? NSScrollView,
           scroll.hasVerticalScroller,
           isInsideWebView(scroll) == false {
            scroll.hasVerticalScroller = false
            #if DEBUG
            NSLog("%@", "[滚动条] 已关闭一个（宽度 \(Int(scroll.frame.width))）")
            #endif
        }
        for sub in view.subviews {
            apply(to: sub)
        }
    }

    private static func isInsideWebView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let node = current {
            if node is WKWebView { return true }
            current = node.superview
        }
        return false
    }
}
