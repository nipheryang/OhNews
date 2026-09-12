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

/// 正文右键菜单里的一项。
///
/// 以后正文里要加功能，往菜单里加一项即可。菜单内容完全由应用决定，
/// 不与 WebKit 的系统菜单叠加。
struct ReaderContextMenuItem {
    let title: String
    /// 点击时执行。选区在点击那一刻现读，所以拿到的永远是最新状态。
    let action: (ReaderSelection) -> Void
}

/// 接管正文区域的右键菜单。
///
/// 为什么不用 `menu(for:)`：macOS 上 `WKWebView` 的右键菜单由 WebProcess 生成，
/// 既不经过 `NSView.menu(for:)`，也不经过普通响应链——覆写它不会生效（实测弹出的
/// 仍是系统的 Look Up / Translate / Copy 那一套）。可靠的做法是在事件分发前拦截。
///
/// 行为：
/// - 右键落在正文里 → 弹应用自己的菜单，并吃掉事件，系统菜单不再出现
/// - 正文里没有任何可用功能 → 弹都不弹，右键什么也不发生
/// - 右键落在别处（列表、侧栏、工具栏）→ 一律放行，不影响别处的系统行为
@MainActor
final class ReaderContextMenuController: NSObject {
    private var monitor: Any?
    private weak var webView: WKWebView?
    private var itemsProvider: () -> [ReaderContextMenuItem] = { [] }

    /// 最近一次划选。右键时用它决定菜单项是否可以点。
    private var lastSelection: ReaderSelection?

    /// 开始接管。重复调用会先卸掉上一个监听。
    func install(in webView: WKWebView, items: @escaping () -> [ReaderContextMenuItem]) {
        self.webView = webView
        self.itemsProvider = items
        uninstall()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// 菜单项变动时更新来源。
    func update(items: @escaping () -> [ReaderContextMenuItem]) {
        itemsProvider = items
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
        case .leftMouseUp:
            // 划选刚结束，顺手记一下，供右键时判断菜单项是否可点。
            refreshSelection()
            return event

        case .rightMouseDown:
            presentMenu(with: event, in: webView)
            // 吃掉事件：系统菜单不再出现。正文里没有可用功能时也不弹任何东西。
            return nil

        default:
            return event
        }
    }

    private func presentMenu(with event: NSEvent, in webView: WKWebView) {
        let items = itemsProvider()
        guard items.isEmpty == false else { return }

        let menu = NSMenu()
        for (index, item) in items.enumerated() {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(performMenuItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = index
            // 没有选中内容时置灰：这些功能都是对选区操作的，可点却什么都不做更费解。
            menuItem.isEnabled = lastSelection != nil
            menu.addItem(menuItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: webView)
    }

    @objc private func performMenuItem(_ sender: NSMenuItem) {
        let items = itemsProvider()
        guard items.indices.contains(sender.tag) else { return }
        let action = items[sender.tag].action
        guard let webView else { return }

        Task { @MainActor in
            // 点击这一刻重读选区：缓存可能已经过期（例如用户中途在别处点过一下）。
            let selection = (try? await Self.readSelection(in: webView)) ?? nil
            self.lastSelection = selection
            guard let selection else { return }
            action(selection)
        }
    }

    // MARK: - 选区

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
        guard let json = raw as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SelectionPayload.self, from: data)
        else { return nil }

        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return ReaderSelection(
            text: text,
            paragraphIndex: payload.index >= 0 ? payload.index : nil
        )
    }

    private struct SelectionPayload: Decodable {
        let text: String
        let index: Int
    }
}
