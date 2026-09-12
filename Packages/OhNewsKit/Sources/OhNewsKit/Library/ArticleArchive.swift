// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 正文当时是以哪种形态呈现的。
///
/// 存档要还原阅读器当时的样子，所以得记住这个——三种形态取正文的方式不同。
public enum ArchivedBodyKind: String, Codable, Hashable, Sendable {
    /// 外链正文，抽取成功。正文在 `article` 里。
    case article
    /// 条目自带的正文（Ask HN、Show HN、部分 RSS）。正文在 `selfPostHTML` 里。
    case selfPost
    /// 没有正文，按降级层级呈现。
    case degraded
}

/// 一篇内容的存档。
///
/// 收藏或稍后读时，把**当时看到的全部材料**冻结在本地：正文、译文、讨论区、
/// 摘要，以及阅读器的显示状态。之后打开收藏直接读它，不再联网。
///
/// 之所以要冻结而不是每次重抓，有两个原因：
/// 1. 重抓要联网、要等，而且取不到时收藏的内容就白丢了；
/// 2. 正文里的段落锚点（`p-<序号>`）只对同一次渲染有效，重抓后段落数量或顺序
///    一变，段落收藏的跳转就会跳错地方。
public struct ArticleArchive: Codable, Hashable, Sendable {
    public let itemID: String
    public let story: Story
    public let archivedAt: Date

    public let bodyKind: ArchivedBodyKind
    /// 外链正文，`bodyKind == .article` 时有效。
    public let article: Article?
    /// 自述帖正文，`bodyKind == .selfPost` 时有效。
    public let selfPostHTML: String?
    /// 降级层级，`bodyKind == .degraded` 时有效。
    public let degradedLevel: ReadingLevel?

    /// 讨论区 HTML（原文）。与正文分开存：讨论区可能比正文先到，也可能取不到。
    public let discussionHTML: String?

    /// 译文。没翻过就是 nil。
    public let translation: ArchivedTranslation?
    /// 存档时显示的是不是译文。打开存档时按它还原。
    public let showsTranslation: Bool

    /// AI 摘要。没有就是 nil。
    public let summary: StorySummary?

    /// 正文解读。没有就是 nil。
    public let insight: ArticleInsight?

    public init(
        itemID: String,
        story: Story,
        archivedAt: Date,
        bodyKind: ArchivedBodyKind,
        article: Article? = nil,
        selfPostHTML: String? = nil,
        degradedLevel: ReadingLevel? = nil,
        discussionHTML: String? = nil,
        translation: ArchivedTranslation? = nil,
        showsTranslation: Bool = false,
        summary: StorySummary? = nil,
        insight: ArticleInsight? = nil
    ) {
        self.itemID = itemID
        self.story = story
        self.archivedAt = archivedAt
        self.bodyKind = bodyKind
        self.article = article
        self.selfPostHTML = selfPostHTML
        self.degradedLevel = degradedLevel
        self.discussionHTML = discussionHTML
        self.translation = translation
        self.showsTranslation = showsTranslation
        self.summary = summary
        self.insight = insight
    }

    /// 正文有没有真正存下来。只存到降级层级说明这次没抓到正文，
    /// 以后如果能抓到，值得补一次。
    public var hasBody: Bool {
        switch bodyKind {
        case .article: article?.html.isEmpty == false
        case .selfPost: selfPostHTML?.isEmpty == false
        case .degraded: false
        }
    }
}

/// 译文在存档里的形态。
///
/// 与 `ArticleTranslation` 分开：那个带内容哈希与模型信息，是缓存有效性的凭据；
/// 存档一旦写成就固定了，不需要再判有效性，只留能渲染的三部分。
public struct ArchivedTranslation: Codable, Hashable, Sendable {
    public let title: String?
    public let articleHTML: String?
    public let discussionHTML: String?

    public init(title: String?, articleHTML: String?, discussionHTML: String?) {
        self.title = title
        self.articleHTML = articleHTML
        self.discussionHTML = discussionHTML
    }
}

/// 存档的本地存储。
///
/// 一条内容一个文件，放在 `Library/Articles/` 下，与 `library.json`、`cache.json`
/// 同级但互不影响：清缓存不会动它，删收藏会连它一起删。
public actor ArchiveStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter directory: 存档目录。传 nil 时用沙盒内应用支持目录下的 `Library/Articles`。
    public init(directory: URL? = nil) {
        let base = directory
            ?? ArchiveStore.defaultDirectory()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // 存档里全是 HTML，转义斜杠会让体积明显变大，也没必要。
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.directory = base
        self.encoder = encoder
        self.decoder = decoder
    }

    public static func defaultDirectory() -> URL {
        LibraryStore.defaultDirectory()
            .appendingPathComponent("Articles", isDirectory: true)
    }

    // MARK: - 读写

    public func save(_ archive: ArticleArchive) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(archive) else { return }
        try? data.write(to: fileURL(for: archive.itemID), options: .atomic)
    }

    public func archive(itemID: String) -> ArticleArchive? {
        guard let data = try? Data(contentsOf: fileURL(for: itemID)) else { return nil }
        return try? decoder.decode(ArticleArchive.self, from: data)
    }

    public func contains(itemID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: itemID).path)
    }

    public func remove(itemID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: itemID))
    }

    public func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 统计

    /// 已存档的条目 ID。从文件名反解不出来，所以逐个读一遍文件头。
    public func itemIDs() -> [String] {
        allArchives().map(\.itemID)
    }

    public func allArchives() -> [ArticleArchive] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url)
            else { return nil }
            return try? decoder.decode(ArticleArchive.self, from: data)
        }
    }

    public func totalSizeInBytes() -> Int64 {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return urls.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    // MARK: - 文件名

    private func fileURL(for itemID: String) -> URL {
        directory.appendingPathComponent(ArchiveStore.fileName(for: itemID))
    }

    /// 把条目 ID 编成安全的文件名。
    ///
    /// 条目 ID 形如 `hn:49670032`，冒号不能直接进文件名。只保留字母、数字与 `-`，
    /// 其余一律写成 `_` 加两位十六进制；`_` 自身也会被编码，所以不存在歧义，
    /// 同一个 ID 永远得到同一个名字。
    public static func fileName(for itemID: String) -> String {
        var result = ""
        for scalar in itemID.unicodeScalars {
            let isPlain = CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
            if isPlain {
                result.unicodeScalars.append(scalar)
            } else {
                result += String(format: "_%02X", scalar.value)
            }
        }
        return result + ".json"
    }
}
