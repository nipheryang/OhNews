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
/// 每 0.4 秒扫一遍，发现谁又被打开了就关掉。属性赋值本身很廉价，
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in applyToAllWindows() }
        }
    }

    private static var resizeObserver: NSObjectProtocol?

    /// 内容刚换过（切频道／切分组）时立刻补几次。
    ///
    /// 列表重建与滚动条被重新装上之间有几十毫秒的间隙，这几次快速补扫就是压掉
    /// 那段"闪一下"——用户看到的一秒其实是等下一次轮询，不是必然。
    static func reapplySoon() {
        for delay in [0.05, 0.15, 0.35, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyToAllWindows()
            }
        }
    }

    private static func applyToAllWindows() {
        for window in NSApp.windows {
            guard let root = window.contentView else { continue }
            apply(to: root)
        }
    }

    private static func apply(to view: NSView) {
        if let scroll = view as? NSScrollView, isInsideWebView(scroll) == false {
            // 两件事一起做，缺一不可：
            //
            // 1. 样式设为 overlay —— **这一条才是"不闪"的关键**。SwiftUI 每次重排都会
            //    把滚动条重新打开（`hasVerticalScroller` 变回 true），而它不受我们控制。
            //    样式是 overlay 时，即使条"在"，**不滚动就不绘制**——于是最坏情况只是
            //    "滚动时浮出一条细条"，不会出现那种闪一下。
            // 2. 顺手把条关掉。能保持住就彻底没有；被 SwiftUI 打开时由第 1 条兜住。
            if scroll.scrollerStyle != .overlay {
                scroll.scrollerStyle = .overlay
            }
            if scroll.hasVerticalScroller {
                scroll.hasVerticalScroller = false
                #if DEBUG
                NSLog("%@", "[滚动条] 已关闭一个（宽度 \(Int(scroll.frame.width))）")
                #endif
            }
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
