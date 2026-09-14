// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 用户主动收藏的一篇文章。
///
/// 与订阅源不是一回事：订阅源按 feed 批量获取，这个是用户看到一篇好文章后
/// 把网址收进来。它只需要一条 `Story`——阅读器要它才能按 url 抓正文——
/// 正文本身走离线存档。
///
/// 与「星标」的区别在来源：星标标记的是自己在信息流里读到的内容，
/// 收藏夹放的是从外面捡回来的东西。
public struct SavedPage: Codable, Hashable, Identifiable, Sendable {
    public let story: Story
    public let savedAt: Date

    public var id: String { story.id }

    public init(story: Story, savedAt: Date) {
        self.story = story
        self.savedAt = savedAt
    }
}

/// 收藏夹的本地存储。
///
/// 单独一个 `pages.json`，与 `library.json`（星标／稍后读／高亮）和
/// `cache.json`（可清空的缓存）都分开：缓存被清空时，用户自己收的文章
/// 不能跟着消失。
public actor SavedPagesStore {
    private static let fileName = "pages.json"

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pages: [SavedPage]

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
        self.pages = (try? Data(contentsOf: url))
            .flatMap { try? decoder.decode([SavedPage].self, from: $0) } ?? []
    }

    /// 全部收藏的单篇，按收藏时间倒序。
    public func all() -> [SavedPage] {
        pages.sorted { $0.savedAt > $1.savedAt }
    }

    public func contains(id: String) -> Bool {
        pages.contains { $0.id == id }
    }

    /// 加入收藏夹。同一条目重复收藏只刷新时间，不产生重复项。
    public func add(_ page: SavedPage) {
        pages.removeAll { $0.id == page.id }
        pages.append(page)
        save()
    }

    public func remove(id: String) {
        pages.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(pages) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
