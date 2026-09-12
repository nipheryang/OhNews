// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 侧栏里除频道之外的固定入口：收藏与稍后读。
///
/// 用带 `library:` 前缀的固定标识充当列表选择值，与频道共用同一条选择通道，
/// 但不会和任何源 ID 冲突（源 ID 形如 `hn:top`、`rss:8f3a…`）。
public enum LibraryEntry: String, CaseIterable, Identifiable, Sendable {
    case collection = "library:collection"
    case readLater = "library:readLater"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .collection: "收藏"
        case .readLater: "稍后读"
        }
    }

    public var systemImage: String {
        switch self {
        case .collection: "bookmark"
        case .readLater: "clock"
        }
    }

    /// 列表为空时的提示。
    public var emptyHint: String {
        switch self {
        case .collection: "在列表里右键条目，或在正文右上角点收藏。"
        case .readLater: "在列表里右键条目，或在正文右上角加入稍后读。"
        }
    }

    public var kind: LibraryStore.Kind {
        switch self {
        case .collection: .collection
        case .readLater: .readLater
        }
    }

    /// 把侧栏的选择值翻译成入口；不是这两个入口时返回 nil。
    public static func matching(_ selectionID: String?) -> LibraryEntry? {
        guard let selectionID else { return nil }
        return LibraryEntry(rawValue: selectionID)
    }
}
