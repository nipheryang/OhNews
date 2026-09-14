// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import WebKit

/// 气泡上被点中的零件。
struct ReaderBubbleHit: Equatable {
    /// 点到的是哪一部分。
    enum Target: String, Equatable {
        /// 那颗圆点：展开菜单。
        case dot
        /// 菜单里的一条：执行动作。
        case item
    }

    let target: Target
    let action: ReaderBubbleAction
}

/// 气泡菜单里的一条动作。
struct ReaderBubbleAction: Equatable {
    /// 字条对应哪一种动作，与脚本里的 `data-ohnews-action` 一一对应。
    enum Kind: String, Equatable {
        /// 把选中的这段文字标成高亮。
        case highlight
        /// 取消这一条高亮。
        case unhighlight
    }

    let kind: Kind
    /// 这条高亮对应的正文：新建时是选中的文字，取消时是存下来的那一段。
    let text: String
    /// 所在段落。定位不到时为 -1。
    let paragraphIndex: Int
}

/// 接管正文里的两件事：划选结束后弹气泡、以及点中气泡菜单项。
///
/// 页面脚本是关着的（`allowsContentJavaScript = false`），所以气泡自己点不动、
/// 选区也不会自己上报"选好了"。两者都只能由应用侧在事件分发前判断：
/// 把 AppKit 的视图坐标换成 CSS 视口坐标，交给 `elementFromPoint` 找。
///
/// **不再接管右键**。高亮改由气泡创建之后，应用自建的右键菜单就没有内容了；
/// 继续吃掉右键只会让系统的「拷贝 / 查找 / 翻译」也跟着消失。现在右键一律放行，
/// WebKit 的原生菜单回来了。
///
/// 也不吃掉左键。气泡浮在正文上方，点它难免会落到下面的文字上，
/// 但由此产生的选区不会再有下文——脚本那头会跳过"点在自己身上"的那一次。
@MainActor
final class ReaderInteractionController: NSObject {
    private var monitor: Any?
    private weak var webView: WKWebView?

    /// 当前文章已有的高亮。划选到已经高亮过的文字时，气泡要给的是「取消高亮」。
    private var highlights: () -> [ReaderHighlight] = { [] }
    private var perform: (ReaderBubbleAction) -> Void = { _ in }

    func install(
        in webView: WKWebView,
        highlights: @escaping () -> [ReaderHighlight],
        perform: @escaping (ReaderBubbleAction) -> Void
    ) {
        self.webView = webView
        self.highlights = highlights
        self.perform = perform
        uninstall()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            // 一律放行：这里只观察，不改变正文里原本会发生的事。
            return event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 收走划选留下的气泡和选区。用过气泡之后调它。
    func clearSelectionBubble(in webView: WKWebView) {
        webView.evaluateJavaScript(ReaderScript.clearSelectionBubble) { _, _ in }
        webView.evaluateJavaScript(ReaderScript.clearSelection) { _, _ in }
    }

    // MARK: - 事件

    private func handle(_ event: NSEvent) {
        guard let webView, event.window === webView.window else { return }
        let point = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(point) else { return }
        guard let css = Self.cssPoint(for: point, in: webView) else { return }

        switch event.type {
        case .leftMouseDown:
            // 按下时就判，抬起时正文里的选区会被点击改掉。
            Task { @MainActor in
                guard let hit = await Self.bubbleHit(at: css, in: webView) else {
                    // 点在别处：把开着的菜单收掉，和点空白处一样。
                    await Self.run(ReaderScript.closeBubbleMenus, in: webView)
                    return
                }

                switch hit.target {
                case .item:
                    self.perform(hit.action)
                case .dot:
                    let script = ReaderScript.openBubbleMenu(
                        text: hit.action.text,
                        index: hit.action.paragraphIndex
                    )
                    await Self.run(script, in: webView)
                }
            }

        case .leftMouseUp:
            // 选完才弹气泡。脚本自己会处理"没选中东西"和"点在自己身上"。
            Task { @MainActor in
                await Self.showSelectionBubble(at: css, in: webView, known: self.highlights())
            }

        default:
            break
        }
    }

    /// 视图坐标 → CSS 视口坐标。
    ///
    /// CSS 视口的原点在左上，AppKit 视图坐标在左下（`WKWebView` 是翻转的，
    /// 但这里两种情形都算一遍，免得依赖某个视图的 `isFlipped` 实现细节）。
    /// 缩放也要除掉，否则放大过的正文会点不准。
    private static func cssPoint(for point: NSPoint, in webView: WKWebView) -> (x: Double, y: Double)? {
        let scale = max(webView.magnification * webView.pageZoom, 0.01)
        let topDownY = webView.isFlipped ? point.y : webView.bounds.height - point.y
        return (Double(point.x) / scale, Double(topDownY) / scale)
    }

    private static func bubbleHit(
        at point: (x: Double, y: Double),
        in webView: WKWebView
    ) async -> ReaderBubbleHit? {
        let script = ReaderScript.hitTestBubble(x: point.x, y: point.y)
        guard let raw = try? await webView.evaluateJavaScript(script),
              let payload = PayloadBox.decode(raw),
              let target = ReaderBubbleHit.Target(rawValue: payload.target),
              let kind = ReaderBubbleAction.Kind(rawValue: payload.action),
              payload.text.isEmpty == false
        else { return nil }

        return ReaderBubbleHit(
            target: target,
            action: ReaderBubbleAction(kind: kind, text: payload.text, paragraphIndex: payload.index)
        )
    }

    private static func run(_ script: String, in webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript(script)
    }

    private static func showSelectionBubble(
        at point: (x: Double, y: Double),
        in webView: WKWebView,
        known: [ReaderHighlight]
    ) async {
        let payload = known.map { ["index": $0.paragraphIndex, "text": $0.text] as [String: Any] }
        let script = ReaderScript.showSelectionBubble(x: point.x, y: point.y, known: payload)
        _ = try? await webView.evaluateJavaScript(script)
    }

    /// 两段脚本返回同一个形状，共用一套解码。
    private struct PayloadBox: Decodable {
        let target: String
        let action: String
        let text: String
        let index: Int

        static func decode(_ raw: Any?) -> PayloadBox? {
            guard let json = raw as? String,
                  let data = json.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(PayloadBox.self, from: data)
            else { return nil }
            return payload
        }
    }
}
