// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 本地缓存。
///
/// 数据量很小（数百条内容），因此用单个 JSON 文件落盘，而不是引入数据库。
/// 好处是可以用临时目录直接跑单元测试，也不需要处理数据模型迁移框架。
///
/// 条目标识从 0.2.0 起带源前缀（`hn:12345`），频道的键也从榜单名改为频道 ID
/// （`hn:top`）。因此快照带上 `schemaVersion`：版本变化时**内容**无法迁移、直接重建，
/// 但**已读记录**会从旧的数字 ID 迁移过来。
public actor CacheStore {
    /// 当前快照结构版本。标识格式变化时递增。
    public static let currentSchemaVersion = 2

    /// 落盘结构。
    ///
    /// 自定义 `init(from:)` 而不是依赖合成实现：合成实现会要求所有字段存在，
    /// 以后新增字段会让旧缓存文件直接解不开。
    private struct Snapshot: Codable {
        var schemaVersion: Int = CacheStore.currentSchemaVersion
        var stories: [String: Story] = [:]
        /// 频道 ID → 条目 ID 顺序。
        var channelOrder: [String: [String]] = [:]
        var readIDs: [String] = []
        var summaries: [String: StorySummary] = [:]
        var translations: [String: ArticleTranslation] = [:]
        var updatedAt: Date = .distantPast

        init() {}

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, stories, channelOrder, readIDs, summaries, translations, updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

            guard version >= CacheStore.currentSchemaVersion else {
                // 旧结构的条目 ID 是纯数字、频道键是榜单名，都没有源信息，无法迁移。
                // 内容直接丢弃重建，只把已读记录迁移过来（旧版本只可能有 HN 的已读）。
                let legacyIDs = (try? container.decodeIfPresent([Int].self, forKey: .readIDs)) ?? []
                schemaVersion = CacheStore.currentSchemaVersion
                stories = [:]
                channelOrder = [:]
                readIDs = legacyIDs.map {
                    SourceIdentifier.itemID(
                        sourceID: HackerNewsSource.sourceID,
                        rawID: String($0)
                    )
                }
                summaries = [:]
                updatedAt = .distantPast
                return
            }

            schemaVersion = version
            stories = try container.decodeIfPresent([String: Story].self, forKey: .stories) ?? [:]
            channelOrder = try container.decodeIfPresent([String: [String]].self, forKey: .channelOrder) ?? [:]
            readIDs = try container.decodeIfPresent([String].self, forKey: .readIDs) ?? []
            summaries = try container.decodeIfPresent([String: StorySummary].self, forKey: .summaries) ?? [:]
            translations = try container.decodeIfPresent([String: ArticleTranslation].self, forKey: .translations) ?? [:]
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot: Snapshot

    /// - Parameter directory: 缓存目录。传 nil 时使用沙盒内的应用支持目录。
    public init(directory: URL? = nil) {
        let base = directory ?? CacheStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let url = base.appendingPathComponent("cache.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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

    // MARK: - 内容

    public func storeStories(_ stories: [Story]) {
        guard stories.isEmpty == false else { return }
        for story in stories {
            snapshot.stories[story.id] = story
        }
        snapshot.updatedAt = Date()
        save()
    }

    public func story(id: String) -> Story? {
        snapshot.stories[id]
    }

    /// 记录某个频道的条目顺序。
    public func storeItemIDs(_ ids: [String], forChannel channelID: String) {
        snapshot.channelOrder[channelID] = ids
        snapshot.updatedAt = Date()
        save()
    }

    public func cachedItemIDs(forChannel channelID: String) -> [String] {
        snapshot.channelOrder[channelID] ?? []
    }

    /// 该频道已缓存的条目，按频道顺序返回。
    public func cachedStories(forChannel channelID: String, limit: Int) -> [Story] {
        cachedItemIDs(forChannel: channelID)
            .prefix(limit)
            .compactMap { snapshot.stories[$0] }
    }

    // MARK: - 已读

    public func markRead(_ id: String) {
        guard snapshot.readIDs.contains(id) == false else { return }
        snapshot.readIDs.append(id)
        save()
    }

    public func markUnread(_ id: String) {
        guard snapshot.readIDs.contains(id) else { return }
        snapshot.readIDs.removeAll { $0 == id }
        save()
    }

    public func isRead(_ id: String) -> Bool {
        snapshot.readIDs.contains(id)
    }

    public func readIDs() -> Set<String> {
        Set(snapshot.readIDs)
    }

    // MARK: - AI 摘要

    /// 读取摘要。`promptVersion` 或 `modelName` 与存入时不符则视为过期。
    public func summary(
        itemID: String,
        promptVersion: String,
        modelName: String
    ) -> StorySummary? {
        guard let summary = snapshot.summaries[itemID] else { return nil }
        return summary.matches(promptVersion: promptVersion, modelName: modelName) ? summary : nil
    }

    public func storeSummary(_ summary: StorySummary) {
        snapshot.summaries[summary.storyID] = summary
        snapshot.updatedAt = Date()
        save()
    }

    /// 批量取出这批条目已有的摘要（不校验版本与模型，仅用于展示）。
    public func summaries(forItemIDs ids: [String]) -> [String: StorySummary] {
        var result: [String: StorySummary] = [:]
        for id in ids {
            if let summary = snapshot.summaries[id] {
                result[id] = summary
            }
        }
        return result
    }

    // MARK: - 译文

    /// 读取译文。内容哈希、模型或 prompt 版本不符时视为过期。
    public func translation(
        itemID: String,
        contentHash: String,
        modelName: String,
        version: String
    ) -> ArticleTranslation? {
        guard let record = snapshot.translations[itemID] else { return nil }
        return record.matches(contentHash: contentHash, modelName: modelName, version: version)
            ? record
            : nil
    }

    public func storeTranslation(_ translation: ArticleTranslation) {
        snapshot.translations[translation.itemID] = translation
        snapshot.updatedAt = Date()
        save()
    }

    // MARK: - 维护

    public func lastUpdatedAt() -> Date {
        snapshot.updatedAt
    }

    /// 缓存文件占用的字节数。设置里展示它，便于用户决定要不要清理。
    public func cacheSizeInBytes() -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public func clear() {
        snapshot = Snapshot()
        save()
    }

    /// 缓存写入失败不应影响主流程：下次写入会再尝试。
    private func save() {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
