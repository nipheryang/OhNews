// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 回收站里的一条。
///
/// 存的是**删除那一刻的完整快照**，而不是一个指针：星标与稍后读标记的是订阅源里的
/// 文章，而订阅源的内容是流动的——取消之后原文未必还在原来的位置，甚至未必还在。
/// 存快照就与来源彻底脱钩，放回时原样写回去即可，不需要重新联网。
public struct TrashedItem: Codable, Hashable, Identifiable, Sendable {
    /// 从哪儿删掉的。放回时据此还原到原处。
    public enum Origin: String, Codable, CaseIterable, Sendable {
        case collection
        case readLater
        case savedPage

        public var title: String {
            switch self {
            case .collection: "星标"
            case .readLater: "稍后读"
            case .savedPage: "收藏夹"
            }
        }
    }

    /// 回收站自己的编号。
    ///
    /// 不用条目的 ID：同一篇文章可以既是星标又是收藏夹的单篇，
    /// 两条都进站时用条目 ID 会撞在一起。
    public let id: String
    /// 文章 ID，用来判断"同一件东西是不是已经在站里了"。
    public let itemID: String
    public let origin: Origin
    /// 星标／稍后读的快照。来源是收藏夹时为 nil。
    public let article: SavedArticle?
    /// 收藏夹单篇的快照。来源是星标／稍后读时为 nil。
    public let page: SavedPage?
    public let deletedAt: Date

    public init(
        id: String = UUID().uuidString,
        itemID: String,
        origin: Origin,
        article: SavedArticle? = nil,
        page: SavedPage? = nil,
        deletedAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.origin = origin
        self.article = article
        self.page = page
        self.deletedAt = deletedAt
    }

    /// 清单里显示什么标题：优先译文标题，其次原文标题。
    public var title: String {
        if let article { return article.translatedTitle ?? article.story.title }
        if let page { return page.story.title }
        return itemID
    }

    /// 快照里的 `Story`。阅读器要它才能按 url 取正文。
    public var story: Story? {
        article?.story ?? page?.story
    }
}

/// 回收站的本地存储。
///
/// 单独一个 `trash.json`，与 `library.json`、`pages.json`、`cache.json` 都分开：
/// 缓存可以被一键清空，回收站不能跟着丢——它正是"删错了还能找回来"的保证。
public actor TrashStore {
    private static let fileName = "trash.json"

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var items: [TrashedItem]

    public init(directory: URL? = nil) {
        let base = directory ?? LibraryStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let url = base.appendingPathComponent(Self.fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.fileURL = url
        self.encoder = encoder
        self.decoder = decoder
        self.items = (try? Data(contentsOf: url))
            .flatMap { try? decoder.decode([TrashedItem].self, from: $0) } ?? []
    }

    /// 全部条目，按删除时间倒序。
    public func all() -> [TrashedItem] {
        items.sorted { $0.deletedAt > $1.deletedAt }
    }

    public func count() -> Int {
        items.count
    }

    /// 放进回收站。
    ///
    /// 同一件东西（同一条目 + 同一个来源）只保留一条：重复放入时刷新删除时间，
    /// 而不是叠成两条让用户看见两份一样的东西。
    public func put(_ item: TrashedItem) {
        items.removeAll { $0.itemID == item.itemID && $0.origin == item.origin }
        items.append(item)
        save()
    }

    public func item(id: String) -> TrashedItem? {
        items.first { $0.id == id }
    }

    /// 取出并移除。放回时用它，避免"取到了但没删掉"。
    public func take(id: String) -> TrashedItem? {
        guard let found = items.first(where: { $0.id == id }) else { return nil }
        items.removeAll { $0.id == id }
        save()
        return found
    }

    /// 彻底删掉一条。
    public func remove(id: String) {
        let before = items.count
        items.removeAll { $0.id == id }
        if items.count != before { save() }
    }

    /// 清空。
    public func removeAll() {
        guard items.isEmpty == false else { return }
        items = []
        save()
    }

    /// 丢掉早于这一时刻的条目，返回丢掉几条。
    @discardableResult
    public func removeItems(deletedBefore cutoff: Date) -> Int {
        let before = items.count
        items.removeAll { $0.deletedAt < cutoff }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    private func save() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
