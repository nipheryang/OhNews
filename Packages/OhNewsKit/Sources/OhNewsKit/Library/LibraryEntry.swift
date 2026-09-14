// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 侧栏里除频道之外的固定入口：星标、高亮、收藏夹、稍后读、回收站。
///
/// 用带 `library:` 前缀的固定标识充当列表选择值，与频道共用同一条选择通道，
/// 但不会和任何源 ID 冲突（源 ID 形如 `hn:top`、`rss:8f3a…`）。
///
/// 顺序即侧栏里的显示顺序。
public enum LibraryEntry: String, CaseIterable, Identifiable, Sendable {
    case collection = "library:collection"
    case highlight = "library:passage"
    case savedPages = "library:pages"
    case readLater = "library:readLater"
    case trash = "library:trash"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .collection: "星标"
        case .highlight: "高亮"
        case .savedPages: "收藏夹"
        case .readLater: "稍后读"
        case .trash: "回收站"
        }
    }

    public var systemImage: String {
        switch self {
        case .collection: "star"
        case .highlight: "highlighter"
        case .savedPages: "bookmark"
        case .readLater: "clock"
        case .trash: "trash"
        }
    }

    /// 列表为空时的提示。
    public var emptyHint: String {
        switch self {
        case .collection: "在列表里右键条目，或在正文右上角点星标。"
        case .highlight: "在正文里选中文段，右键标记高亮。"
        case .savedPages: "点分组旁的加号，粘贴一个网址收进来。"
        case .readLater: "在列表里右键条目，或在正文右上角加入稍后读。"
        case .trash: "删掉的文章会先放到这里，可以放回原处。"
        }
    }

    /// 是否有「加入」入口（分组标题旁边的加号）。
    ///
    /// 目前只有收藏夹需要：星标、高亮、稍后读都由阅读时的动作产生。
    public var addActionTitle: String? {
        switch self {
        case .savedPages: "添加单篇文章"
        case .collection, .highlight, .readLater, .trash: nil
        }
    }

    /// 把侧栏的选择值翻译成入口；不是这些入口时返回 nil。
    public static func matching(_ selectionID: String?) -> LibraryEntry? {
        guard let selectionID else { return nil }
        return LibraryEntry(rawValue: selectionID)
    }
}
