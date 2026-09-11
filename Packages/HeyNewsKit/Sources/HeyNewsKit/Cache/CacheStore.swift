import Foundation

/// 本地缓存。
///
/// V0 的数据量很小（数百条内容），因此用单个 JSON 文件落盘，而不是引入数据库。
/// 好处是可以用临时目录直接跑单元测试，也不需要处理数据模型迁移。
public actor CacheStore {
    private struct Snapshot: Codable {
        var stories: [String: Story] = [:]
        var listOrder: [String: [Int]] = [:]
        var readIDs: [Int] = []
        var updatedAt: Date = .distantPast
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
        return base.appendingPathComponent("HeyNews", isDirectory: true)
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
