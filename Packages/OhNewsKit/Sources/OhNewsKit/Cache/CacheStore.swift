import Foundation

/// 本地缓存。
///
/// V0 的数据量很小（数百条内容），因此用单个 JSON 文件落盘，而不是引入数据库。
/// 好处是可以用临时目录直接跑单元测试，也不需要处理数据模型迁移。
public actor CacheStore {
    /// 落盘结构。
    ///
    /// 自定义 `init(from:)` 而不是依赖合成实现：合成实现会要求所有字段存在，
    /// 以后新增字段会让旧缓存文件直接解不开。
    private struct Snapshot: Codable {
        var stories: [String: Story] = [:]
        var listOrder: [String: [Int]] = [:]
        var readIDs: [Int] = []
        var summaries: [String: StorySummary] = [:]
        var updatedAt: Date = .distantPast

        init() {}

        private enum CodingKeys: String, CodingKey {
            case stories, listOrder, readIDs, summaries, updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stories = try container.decodeIfPresent([String: Story].self, forKey: .stories) ?? [:]
            listOrder = try container.decodeIfPresent([String: [Int]].self, forKey: .listOrder) ?? [:]
            readIDs = try container.decodeIfPresent([Int].self, forKey: .readIDs) ?? []
            summaries = try container.decodeIfPresent([String: StorySummary].self, forKey: .summaries) ?? [:]
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
            snapshot.stories[String(story.id)] = story
        }
        snapshot.updatedAt = Date()
        save()
    }

    public func story(id: Int) -> Story? {
        snapshot.stories[String(id)]
    }

    /// 记录某个榜单的条目顺序。
    public func storeListIDs(_ ids: [Int], for list: StoryList) {
        snapshot.listOrder[list.rawValue] = ids
        snapshot.updatedAt = Date()
        save()
    }

    public func cachedIDs(for list: StoryList) -> [Int] {
        snapshot.listOrder[list.rawValue] ?? []
    }

    /// 该榜单已缓存的条目，按榜单顺序返回。
    public func cachedStories(for list: StoryList, limit: Int) -> [Story] {
        cachedIDs(for: list)
            .prefix(limit)
            .compactMap { snapshot.stories[String($0)] }
    }

    // MARK: - 已读

    public func markRead(_ id: Int) {
        guard snapshot.readIDs.contains(id) == false else { return }
        snapshot.readIDs.append(id)
        save()
    }

    public func markUnread(_ id: Int) {
        guard snapshot.readIDs.contains(id) else { return }
        snapshot.readIDs.removeAll { $0 == id }
        save()
    }

    public func isRead(_ id: Int) -> Bool {
        snapshot.readIDs.contains(id)
    }

    public func readIDs() -> Set<Int> {
        Set(snapshot.readIDs)
    }

    // MARK: - AI 摘要

    /// 读取摘要。`promptVersion` 或 `modelName` 与存入时不符则视为过期。
    public func summary(
        storyID: Int,
        promptVersion: String,
        modelName: String
    ) -> StorySummary? {
        guard let summary = snapshot.summaries[String(storyID)] else { return nil }
        return summary.matches(promptVersion: promptVersion, modelName: modelName) ? summary : nil
    }

    public func storeSummary(_ summary: StorySummary) {
        snapshot.summaries[String(summary.storyID)] = summary
        snapshot.updatedAt = Date()
        save()
    }

    /// 批量取出这批条目已有的摘要（不校验版本与模型，仅用于展示）。
    public func summaries(forStoryIDs ids: [Int]) -> [Int: StorySummary] {
        var result: [Int: StorySummary] = [:]
        for id in ids {
            if let summary = snapshot.summaries[String(id)] {
                result[id] = summary
            }
        }
        return result
    }

    // MARK: - 维护

    public func lastUpdatedAt() -> Date {
        snapshot.updatedAt
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
