// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 一篇文章的保存记录（收藏或稍后读）。
///
/// 存完整的 `Story` 快照，而不只是标题与链接：收藏列表要能显示来源、分数，
/// 用户点开时阅读器也要有 `Story` 才能按 url 重新抓取正文。正文 HTML 本身
/// 不存——按 url 重抓即可，存下来会让文件迅速变大。
///
/// 另外带上译文标题与 AI 摘要：它们让列表**不必等打开内容**就能显示中文。
/// 存在这里而不是每次去读存档，是因为列表要一次性拿到全部条目，
/// 逐个读存档文件会变成几十次磁盘访问。
public struct SavedArticle: Codable, Hashable, Identifiable, Sendable {
    public let story: Story
    public let savedAt: Date
    /// 收藏时已有的译文标题。列表用它代替英文原标题。
    public let translatedTitle: String?
    /// 收藏时已有的 AI 摘要。
    public let summary: StorySummary?

    public var id: String { story.id }

    public init(
        story: Story,
        savedAt: Date,
        translatedTitle: String? = nil,
        summary: StorySummary? = nil
    ) {
        self.story = story
        self.savedAt = savedAt
        self.translatedTitle = translatedTitle
        self.summary = summary
    }
}

/// 正文里被标记高亮的一段。
///
/// 只存选中的那段文字（用户的选择），外加段落序号用于跳回原文。
///
/// 名字保留了早期的「段落收藏」：`passages` 是 `library.json` 里的键，
/// 改掉它会读不出用户已有的数据。界面上一律叫「高亮」。
public struct SavedPassage: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let itemID: String
    /// 所属文章标题，收藏列表脱离原文时也要能看懂。
    public let articleTitle: String
    public let text: String
    /// 段落序号。阅读器会为每个块级元素生成 `p-<序号>` 的锚点。
    public let paragraphIndex: Int
    public let savedAt: Date

    public init(
        id: String = UUID().uuidString,
        itemID: String,
        articleTitle: String,
        text: String,
        paragraphIndex: Int,
        savedAt: Date
    ) {
        self.id = id
        self.itemID = itemID
        self.articleTitle = articleTitle
        self.text = text
        self.paragraphIndex = paragraphIndex
        self.savedAt = savedAt
    }
}

/// 收藏与稍后读的本地存储。
///
/// 与 `CacheStore` 分文件存放：缓存可以被用户一键清空，收藏不能跟着丢。
public actor LibraryStore {
    /// 保存的两种用途。一篇文章可以同时是收藏和稍后读，所以各自一个集合。
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case collection
        case readLater
    }

    /// 高亮的文字上限。一次划选整篇没有意义，也容易把文件撑大。
    public static let maxPassageLength = 2000

    private struct Snapshot: Codable {
        var version = 1
        var collections: [SavedArticle] = []
        var readLater: [SavedArticle] = []
        var passages: [SavedPassage] = []
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot: Snapshot

    /// - Parameter directory: 存储目录。传 nil 时使用沙盒内的应用支持目录。
    public init(directory: URL? = nil) {
        let base = directory ?? LibraryStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let url = base.appendingPathComponent("library.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.fileURL = url
        self.encoder = encoder
        self.decoder = decoder

        if let data = try? Data(contentsOf: url),
           let loaded = try? decoder.decode(Snapshot.self, from: data) {
            self.snapshot = loaded
        } else {
            self.snapshot = Snapshot()
        }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("OhNews", isDirectory: true)
    }

    // MARK: - 文章级

    /// 某个用途下的全部文章，按保存时间倒序。
    public func articles(_ kind: Kind) -> [SavedArticle] {
        list(for: kind).sorted { $0.savedAt > $1.savedAt }
    }

    public func containsArticle(itemID: String, kind: Kind) -> Bool {
        list(for: kind).contains { $0.id == itemID }
    }

    /// 加入收藏／稍后读。已存在则只刷新保存时间，不产生重复项。
    public func addArticle(_ article: SavedArticle, kind: Kind) {
        var items = list(for: kind)
        items.removeAll { $0.id == article.id }
        items.append(article)
        setList(items, for: kind)
    }

    public func removeArticle(itemID: String, kind: Kind) {
        var items = list(for: kind)
        items.removeAll { $0.id == itemID }
        setList(items, for: kind)
    }

    /// 切换状态，返回切换后是否处于保存状态。
    @discardableResult
    public func toggleArticle(_ article: SavedArticle, kind: Kind) -> Bool {
        if containsArticle(itemID: article.id, kind: kind) {
            removeArticle(itemID: article.id, kind: kind)
            return false
        }
        addArticle(article, kind: kind)
        return true
    }

    /// 更新已保存条目的译文标题与摘要，不动保存时间（排序靠它）。
    ///
    /// 用户可能先收藏、后翻译：那时条目已经在列表里了，但还没有中文可显示。
    public func updateMetadata(
        itemID: String,
        translatedTitle: String?,
        summary: StorySummary?
    ) {
        for kind in Kind.allCases {
            var items = list(for: kind)
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            let old = items[index]
            items[index] = SavedArticle(
                story: old.story,
                savedAt: old.savedAt,
                translatedTitle: translatedTitle ?? old.translatedTitle,
                summary: summary ?? old.summary
            )
            setList(items, for: kind)
        }
    }

    // MARK: - 段落级

    /// 全部段落收藏，按保存时间倒序。
    public func allPassages() -> [SavedPassage] {
        snapshot.passages.sorted { $0.savedAt > $1.savedAt }
    }

    public func passages(itemID: String) -> [SavedPassage] {
        snapshot.passages
            .filter { $0.itemID == itemID }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// 同一篇文章里的同一段文字不重复收藏。
    public func hasPassage(itemID: String, text: String) -> Bool {
        snapshot.passages.contains { $0.itemID == itemID && $0.text == text }
    }

    /// 保存一段正文。返回 nil 表示这段文字不符合保存条件（空、过长、重复）。
    @discardableResult
    public func addPassage(_ passage: SavedPassage) -> SavedPassage? {
        let text = passage.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, text.count <= Self.maxPassageLength else { return nil }
        guard hasPassage(itemID: passage.itemID, text: text) == false else { return nil }

        var stored = passage
        stored = SavedPassage(
            id: passage.id,
            itemID: passage.itemID,
            articleTitle: passage.articleTitle,
            text: text,
            paragraphIndex: passage.paragraphIndex,
            savedAt: passage.savedAt
        )
        snapshot.passages.append(stored)
        save()
        return stored
    }

    public func removePassage(id: String) {
        snapshot.passages.removeAll { $0.id == id }
        save()
    }

    /// 按「文章 + 原文」删一条高亮。返回删掉了几条（正常是 0 或 1）。
    ///
    /// 正文里点那条高亮时只拿得到文字和段落号，拿不到内部 id，所以要有这条路。
    /// 文字按原样比较：存进去时已经去掉过首尾空白，读出来也去掉再比。
    @discardableResult
    public func removePassage(itemID: String, text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return 0 }

        let before = snapshot.passages.count
        snapshot.passages.removeAll { $0.itemID == itemID && $0.text == trimmed }
        let removed = before - snapshot.passages.count
        if removed > 0 { save() }
        return removed
    }

    // MARK: - 内部

    private func list(for kind: Kind) -> [SavedArticle] {
        switch kind {
        case .collection: snapshot.collections
        case .readLater: snapshot.readLater
        }
    }

    private func setList(_ items: [SavedArticle], for kind: Kind) {
        switch kind {
        case .collection: snapshot.collections = items
        case .readLater: snapshot.readLater = items
        }
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
