// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
import WebKit

/// 一次划选的结果。
struct ReaderSelection: Equatable {
    /// 选中的文字，已去掉首尾空白。
    let text: String
    /// 选中的文字落在第几段。定位不到时为 nil。
    let paragraphIndex: Int?
}

/// 菜单是对谁操作的。
///
/// 正文里现在有两类可操作对象，菜单项的语义完全不同：一类是刚划选的文字
/// （只能"标成高亮"），一类是已经高亮的那句话（只能"取消高亮"）。
/// 分开表达，菜单项就不必自己再判断一次。
enum ReaderMenuTarget {
    /// 正文里划选的一段文字。
    case selection(ReaderSelection)
    /// 正文里已经高亮的一句话。
    case highlight(ReaderHighlight)
}

/// 正文菜单里的一项。
///
/// 以后正文里要加功能，往菜单里加一项即可。菜单内容完全由应用决定，
/// 不与 WebKit 的系统菜单叠加。
struct ReaderContextMenuItem {
    let title: String
    /// 点击时执行。划选内容在点击那一刻现读，所以拿到的永远是最新状态。
    let action: (ReaderMenuTarget) -> Void
}

/// 接管正文区域里会被应用用到的那几次点击。
///
/// 为什么不用 `menu(for:)`：macOS 上 `WKWebView` 的右键菜单由 WebProcess 生成，
/// 既不经过 `NSView.menu(for:)`，也不经过普通响应链——覆写它不会生效（实测弹出的
/// 仍是系统的 Look Up / Translate / Copy 那一套）。可靠的做法是在事件分发前拦截。
///
/// 为什么点击也要拦：阅读器关着页面脚本，正文自己不会上报"点到了高亮"。
/// 页面里的 CSS 能给出悬停效果，但"点中了哪一句"只能由应用侧读文档判断。
///
/// 行为：
/// - 右键落在正文里 → 弹应用自己的菜单，并吃掉事件，系统菜单不再出现
/// - 左键点在高亮上（不是拖选）→ 弹针对这条高亮的菜单
/// - 正文里没有任何可用功能 → 弹都不弹，点击什么也不发生
/// - 点击落在别处（列表、侧栏、工具栏）→ 一律放行，不影响别处的系统行为
@MainActor
final class ReaderContextMenuController: NSObject {
    private var monitor: Any?
    private weak var webView: WKWebView?
    /// 划选文字时的菜单项。
    private var itemsProvider: () -> [ReaderContextMenuItem] = { [] }
    /// 点在高亮上时的菜单项。
    private var highlightItemsProvider: (ReaderHighlight) -> [ReaderContextMenuItem] = { _ in [] }

    /// 最近一次划选。右键时用它决定菜单项是否可以点。
    private var lastSelection: ReaderSelection?

    /// 当前菜单操作的对象。菜单项回调要靠它，所以得留着。
    private var activeTarget: ReaderMenuTarget?

    /// 左键按下的位置。用来区分「点一下」和「拖着划选」。
    private var mouseDownPoint: NSPoint?

    /// 开始接管。重复调用会先卸掉上一个监听。
    func install(
        in webView: WKWebView,
        items: @escaping () -> [ReaderContextMenuItem],
        highlightItems: @escaping (ReaderHighlight) -> [ReaderContextMenuItem]
    ) {
        self.webView = webView
        self.itemsProvider = items
        self.highlightItemsProvider = highlightItems
        uninstall()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// 菜单项变动时更新来源。
    func update(
        items: @escaping () -> [ReaderContextMenuItem],
        highlightItems: @escaping (ReaderHighlight) -> [ReaderContextMenuItem]
    ) {
        itemsProvider = items
        highlightItemsProvider = highlightItems
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: - 事件

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let webView, event.window === webView.window else { return event }
        let point = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(point) else { return event }

        switch event.type {
        case .leftMouseDown:
            mouseDownPoint = point
            return event

        case .leftMouseUp:
            let pressed = mouseDownPoint
            mouseDownPoint = nil
            // 划选刚结束，顺手记一下，供右键时判断菜单项是否可点。
            refreshSelection()

            // 只处理"点一下"。拖着划选时不该弹菜单——那是用户在选文字。
            if let pressed, Self.isClick(from: pressed, to: point) {
                presentMenuForHighlight(at: point, in: webView)
            }
            return event

        case .rightMouseDown:
            presentMenu(with: event, at: point, in: webView)
            // 吃掉事件：系统菜单不再出现。正文里没有可用功能时也不弹任何东西。
            return nil

        default:
            return event
        }
    }

    private static func isClick(from start: NSPoint, to end: NSPoint) -> Bool {
        abs(end.x - start.x) < 3 && abs(end.y - start.y) < 3
    }

    /// 右键：先看有没有划选，没有再看是不是压在高亮上。
    private func presentMenu(with event: NSEvent, at point: NSPoint, in webView: WKWebView) {
        // 划选是对"选中的文字"操作，优先级最高。
        if let selection = lastSelection {
            present(
                itemsProvider(),
                target: .selection(selection),
                event: event,
                at: point,
                in: webView
            )
            return
        }

        // 没有划选：要读一次文档才知道是不是压在高亮上，这一步是异步的。
        // 事件已经被吃掉，这里晚几毫秒弹菜单不会被系统菜单抢在前面。
        Task { @MainActor in
            if let hit = await Self.highlightHit(at: point, in: webView) {
                self.present(
                    self.highlightItemsProvider(hit),
                    target: .highlight(hit),
                    event: event,
                    at: point,
                    in: webView
                )
            } else {
                // 什么也没命中：仍然弹一次，把菜单项置灰。
                // 完全不弹的话，用户会以为这个功能没有。
                self.present(self.itemsProvider(), target: nil, event: event, at: point, in: webView)
            }
        }
    }

    /// 左键点在高亮上：弹针对这条高亮的菜单。
    private func presentMenuForHighlight(at point: NSPoint, in webView: WKWebView) {
        Task { @MainActor in
            guard let hit = await Self.highlightHit(at: point, in: webView) else { return }
            let items = self.highlightItemsProvider(hit)
            guard items.isEmpty == false else { return }
            self.present(items, target: .highlight(hit), event: nil, at: point, in: webView)
        }
    }

    /// 弹出菜单。
    ///
    /// 右键走 `popUpContextMenu`：沿用系统右键菜单的位置与手感。
    /// 左键点击没有合适的现成事件可传，改用 `popUp(positioning:at:in:)` 按点击位置弹。
    private func present(
        _ items: [ReaderContextMenuItem],
        target: ReaderMenuTarget?,
        event: NSEvent?,
        at point: NSPoint,
        in webView: WKWebView
    ) {
        guard items.isEmpty == false else { return }

        activeTarget = target

        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(performMenuItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            // 没命中任何对象时置灰：这些功能都是对具体内容操作的，
            // 可点却什么都不做更费解。
            menuItem.isEnabled = target != nil
            menu.addItem(menuItem)
        }

        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: webView)
        } else {
            menu.popUp(positioning: nil, at: point, in: webView)
        }
    }

    @objc private func performMenuItem(_ sender: NSMenuItem) {
        let target = activeTarget
        guard let target else { return }
        let items = switch target {
        case .selection: itemsProvider()
        case .highlight: highlightItemsProvider(highlightFrom(target))
        }
        guard items.indices.contains(sender.tag) else { return }
        let action = items[sender.tag].action
        guard let webView else { return }

        guard case .selection = target else {
            action(target)
            return
        }

        Task { @MainActor in
            // 点击这一刻重读选区：缓存可能已经过期（例如用户中途在别处点过一下）。
            let selection = (try? await Self.readSelection(in: webView)) ?? nil
            self.lastSelection = selection
            guard let selection else { return }
            action(.selection(selection))
        }
    }

    private func highlightFrom(_ target: ReaderMenuTarget) -> ReaderHighlight {
        switch target {
        case .highlight(let hit):
            return hit
        case .selection(let selection):
            return ReaderHighlight(
                paragraphIndex: selection.paragraphIndex ?? -1,
                text: selection.text
            )
        }
    }

    // MARK: - 选区与命中

    /// 重新读一次选区并缓存。读不到就当作没有选中。
    func refreshSelection(completion: ((ReaderSelection?) -> Void)? = nil) {
        guard let webView else {
            lastSelection = nil
            completion?(nil)
            return
        }
        Task { @MainActor in
            let selection = (try? await Self.readSelection(in: webView)) ?? nil
            self.lastSelection = selection
            completion?(selection)
        }
    }

    /// 读窗口里的选区，并给出它所在的段落。
    ///
    /// 阅读器关着页面脚本，但那只限制 web content 的脚本，应用侧的
    /// `evaluateJavaScript` 不受影响。
    private static func readSelection(in webView: WKWebView) async throws -> ReaderSelection? {
        let raw = try await webView.evaluateJavaScript(ReaderScript.readSelection)
        guard let payload = decodePayload(raw) else { return nil }

        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return ReaderSelection(
            text: text,
            paragraphIndex: payload.index >= 0 ? payload.index : nil
        )
    }

    /// 视图坐标上这一点有没有落在一条高亮里。
    private static func highlightHit(at point: NSPoint, in webView: WKWebView) async -> ReaderHighlight? {
        // CSS 视口坐标的原点在左上，AppKit 视图坐标在左下（`WKWebView` 是翻转的，
        // 但这里按两种情形都算一遍，免得依赖某个视图的 `isFlipped` 实现细节）。
        let scale = max(webView.magnification * webView.pageZoom, 0.01)
        let topDownY = webView.isFlipped ? point.y : webView.bounds.height - point.y
        let script = ReaderScript.hitTestHighlight(
            x: Double(point.x) / scale,
            y: Double(topDownY) / scale
        )

        guard let raw = try? await webView.evaluateJavaScript(script),
              let payload = decodePayload(raw)
        else { return nil }

        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return ReaderHighlight(paragraphIndex: payload.index, text: text)
    }

    /// 两段脚本返回同一个形状，共用一套解码。
    private static func decodePayload(_ raw: Any?) -> SelectionPayload? {
        guard let json = raw as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SelectionPayload.self, from: data)
        else { return nil }
        return payload
    }

    private struct SelectionPayload: Decodable {
        let text: String
        let index: Int
    }
}
