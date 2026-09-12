// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 侧栏频道选择的持久化。
///
/// 只存一个频道 ID（例如 `hn:top`、`rss:9a1f…`），用于重启后回到上次浏览的频道。
/// 读到 `nil` 表示没存过；读到已不存在的频道（例如源被删除）由调用方回落到默认频道。
public struct SelectionPersistence {
    private static let key = "ui.selectedChannel"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> String? {
        let value = defaults.string(forKey: Self.key)
        guard let value, value.isEmpty == false else { return nil }
        return value
    }

    public func save(_ channelID: String?) {
        guard let channelID, channelID.isEmpty == false else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(channelID, forKey: Self.key)
    }
}
