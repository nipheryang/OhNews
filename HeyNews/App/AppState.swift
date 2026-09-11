import Foundation
import HeyNewsKit
import Observation

/// 应用级状态。
///
/// 只有这里持有 UI 状态；网络与缓存分别由 `HNClient`、`CacheStore` 两个 actor 负责。
@MainActor
@Observable
final class AppState {
    /// 列表一次展示多少条。
    static let displayLimit = 30

    var selectedList: StoryList? = .top
    var stories: [Story] = []
    var readIDs: Set<Int> = []
    var selectedStoryID: Int?
    var isLoading = false
    var lastErrorMessage: String?
    var lastUpdatedAt: Date?

    private let client: HNClient
    private let cache: CacheStore

    init(client: HNClient = HNClient(), cache: CacheStore = CacheStore()) {
        self.client = client
        self.cache = cache
    }

    var activeList: StoryList { selectedList ?? .top }

    var selectedStory: Story? {
        guard let selectedStoryID else { return nil }
        return stories.first { $0.id == selectedStoryID }
    }

    // MARK: - 加载

    /// 切换榜单：先渲染缓存，再拉网络。
    func loadList(_ list: StoryList) async {
        selectedStoryID = nil
        lastErrorMessage = nil

        let cachedStories = await cache.cachedStories(for: list, limit: Self.displayLimit)
        let cachedReadIDs = await cache.readIDs()
        readIDs = cachedReadIDs
        stories = cachedStories
        lastUpdatedAt = await cache.lastUpdatedAt()

        await fetch(list)
    }

    /// 用户主动刷新。
    func refresh() async {
        await fetch(activeList)
    }

    /// 网络拉取。先取 ID 列表，再逐条取详情并增量上屏。
    private func fetch(_ list: StoryList) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let ids = try await client.fetchStoryIDs(for: list)
            await cache.storeListIDs(ids, for: list)

            var collected: [Story] = []
            for id in ids.prefix(Self.displayLimit * 2) {
                if collected.count >= Self.displayLimit { break }
                guard let story = try? await client.fetchStory(id: id) else { continue }
                collected.append(story)
                await cache.storeStories([story])
                // 增量上屏：不必等 30 条全部取完才看到内容。
                stories = collected
            }

            readIDs = await cache.readIDs()
            lastUpdatedAt = await cache.lastUpdatedAt()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    // MARK: - 交互

    /// 选中一条新闻：标记已读并落到详情区。
    func select(_ story: Story) async {
        selectedStoryID = story.id
        guard readIDs.contains(story.id) == false else { return }
        readIDs.insert(story.id)
        await cache.markRead(story.id)
    }

    func isRead(_ story: Story) -> Bool {
        readIDs.contains(story.id)
    }

    private static func message(for error: Error) -> String {
        if let clientError = error as? HNClientError, case .http(let status) = clientError {
            return "HN 接口返回 \(status)，稍后重试即可，缓存内容仍可阅读。"
        }
        return "网络请求失败：\((error as NSError).localizedDescription)"
    }
}
