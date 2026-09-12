// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// Hacker News 作为信息源的静态定义：源标识、频道标识，以及与 `StoryList` 的映射。
///
/// 这里只放标识与映射这类纯逻辑。频道的中文展示名属于界面层，由 app 负责映射；
/// 抓到数据的实现由 app 层的 provider 负责。
public enum HackerNewsSource {
    /// 内置源的固定 ID，与 `SourceKind.hackerNews.identifierPrefix` 保持一致。
    public static let sourceID = SourceKind.hackerNews.identifierPrefix

    public static let source = NewsSource(
        id: sourceID,
        kind: .hackerNews,
        name: SourceKind.hackerNews.displayName
    )

    /// `StoryList` 对应的频道 ID，例如 `hn:top`。
    public static func channelID(for list: StoryList) -> String {
        SourceIdentifier.channelID(sourceID: sourceID, key: list.rawValue)
    }

    /// HN 条目 ID，形如 `hn:12345`。
    public static func itemID(for number: Int) -> String {
        SourceIdentifier.itemID(sourceID: sourceID, rawID: String(number))
    }

    /// 频道 ID 反查 `StoryList`。非 HN 频道（例如 RSS）返回 nil。
    public static func list(forChannelID channelID: String) -> StoryList? {
        guard let key = key(fromIdentifier: channelID) else { return nil }
        return StoryList(rawValue: key)
    }

    /// 从条目 ID 取回 HN 的数字 ID。前缀不是 `hn`、或后缀不是数字时返回 nil。
    ///
    /// HN 的接口（Firebase 与 Algolia）都只认数字 ID，而应用内部统一用带前缀的字符串。
    public static func numericID(fromItemID itemID: String) -> Int? {
        key(fromIdentifier: itemID).flatMap(Int.init)
    }

    /// 从标识中取出源内键（`hn:top` → `top`）。前缀不是 `hn` 时返回 nil。
    public static func key(fromIdentifier identifier: String) -> String? {
        let parts = identifier.split(
            separator: Character(SourceIdentifier.separator),
            maxSplits: 1
        )
        guard parts.count == 2, parts[0] == Substring(sourceID) else { return nil }
        return String(parts[1])
    }
}
