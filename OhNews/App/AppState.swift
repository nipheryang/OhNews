import Foundation
import OhNewsKit
import Observation

/// AI 功能当前是否可用。
enum AIStatus: Equatable {
    /// 没有配置密钥或未启用。
    case notConfigured
    case ready
    case failed(String)
}

/// 阅读器当前的正文状态。
enum ReaderState: Equatable {
    case idle
    case loading
    /// 外链正文抽取成功。
    case article(Article)
    /// HN 自述帖：正文就是 HN 上的文本。
    case selfPost(html: String)
    /// 没有正文，按降级级别呈现。
    case degraded(ReadingLevel)
    case failed(String)
}

/// 应用级状态。
///
/// 只有这里持有 UI 状态；网络、缓存、AI 分别由 `HNClient`、`CacheStore`、`SummaryService`
/// 三个 actor 负责。摘要的并发调度放在这里，是因为它需要随着列表与界面状态变化。
@MainActor
@Observable
final class AppState {
    /// 列表一次展示多少条。
    static let displayLimit = 30
    /// 列表加载后自动生成摘要的条数上限。
    static let summaryPrefetchLimit = 12
    /// 同时进行的摘要请求数。
    private static let summaryConcurrency = 3

    /// 侧栏当前选中的榜单。重启后沿用上次的选择，默认 Top。
    var selectedList: StoryList? = .top {
        didSet { selectionPersistence.save(selectedList) }
    }
    var stories: [Story] = []
    var readIDs: Set<String> = []
    var summaries: [String: StorySummary] = [:]
    var selectedStoryID: String?
    var isLoading = false
    var lastErrorMessage: String?
    var lastUpdatedAt: Date?
    var aiStatus: AIStatus = .notConfigured
    var readerState: ReaderState = .idle
    var config: AIProviderConfig

    private let client: HNClient
    private let cache: CacheStore
    private let summaryService: SummaryService
    private var generatingIDs: Set<String> = []
    private var articleTask: Task<Void, Never>?
    private let selectionPersistence = SelectionPersistence()
    /// 正文抽取器要在首次使用时才创建 WKWebView，且不需要参与观察。
    @ObservationIgnored private lazy var extractor = ArticleExtractor()

    init(
        client: HNClient = HNClient(),
        cache: CacheStore = CacheStore(),
        config: AIProviderConfig = ConfigPersistence.load()
    ) {
        self.client = client
        self.cache = cache
        self.config = config
        self.summaryService = SummaryService(cache: cache, config: config)

        // 在 `init` 里赋值不会触发 `didSet`，因此恢复选择不会反向写一遍。
        if let restored = selectionPersistence.load() {
            selectedList = restored
        }
    }

    var activeList: StoryList { selectedList ?? .top }

    var selectedStory: Story? {
        guard let selectedStoryID else { return nil }
        return stories.first { $0.id == selectedStoryID }
    }

    // MARK: - 加载

    /// 切换榜单：先渲染缓存，再拉网络，最后补齐 AI 摘要。
    func loadList(_ list: StoryList) async {
        selectedStoryID = nil
        lastErrorMessage = nil
        articleTask?.cancel()
        readerState = .idle

        let channelID = HackerNewsSource.channelID(for: list)
        let cachedStories = await cache.cachedStories(
            forChannel: channelID,
            limit: Self.displayLimit
        )
        readIDs = await cache.readIDs()
        stories = cachedStories
        lastUpdatedAt = await cache.lastUpdatedAt()
        summaries = await cache.summaries(forItemIDs: cachedStories.map(\.id))

        await fetch(list)
        await prefetchSummaries()
    }

    /// 用户主动刷新。
    func refresh() async {
        await fetch(activeList)
        await prefetchSummaries()
    }

    /// 网络拉取。先取 ID 列表，再逐条取详情并增量上屏。
    private func fetch(_ list: StoryList) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let ids = try await client.fetchStoryIDs(for: list)
            await cache.storeItemIDs(
                ids.map { HackerNewsSource.itemID(for: $0) },
                forChannel: HackerNewsSource.channelID(for: list)
            )

            var collected: [Story] = []
            for id in ids.prefix(Self.displayLimit * 2) {
                if collected.count >= Self.displayLimit { break }
                if Task.isCancelled { return }
                guard let story = try? await client.fetchStory(id: id) else { continue }
                collected.append(story)
                await cache.storeStories([story])
                // 增量上屏：不必等 30 条全部取完才看到内容。
                stories = collected
            }

            readIDs = await cache.readIDs()
            summaries = await cache.summaries(forItemIDs: collected.map(\.id))
            lastUpdatedAt = await cache.lastUpdatedAt()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    // MARK: - AI 摘要

    func refreshAIStatus() async {
        guard config.isEnabled else {
            aiStatus = .notConfigured
            return
        }
        let ready = await summaryService.isConfigured()
        aiStatus = ready ? .ready : .notConfigured
    }

    /// 为列表前若干条生成摘要。已有缓存的条目直接跳过。
    func prefetchSummaries() async {
        guard config.isEnabled else { return }

        let ready = await summaryService.isConfigured()
        guard ready else {
            aiStatus = .notConfigured
            return
        }
        aiStatus = .ready

        let pending = Array(stories.prefix(Self.summaryPrefetchLimit))
            .filter { summaries[$0.id] == nil }
        guard pending.isEmpty == false else { return }

        await withTaskGroup(of: Void.self) { group in
            var index = 0
            while index < min(Self.summaryConcurrency, pending.count) {
                let story = pending[index]
                index += 1
                group.addTask { await self.generateSummary(for: story) }
            }
            // 每完成一条就补一条，始终维持固定并发数。
            while await group.next() != nil {
                guard Task.isCancelled == false, index < pending.count else { continue }
                let story = pending[index]
                index += 1
                group.addTask { await self.generateSummary(for: story) }
            }
        }
    }

    func isGeneratingSummary(for story: Story) -> Bool {
        generatingIDs.contains(story.id)
    }

    private func generateSummary(for story: Story) async {
        guard Task.isCancelled == false else { return }
        generatingIDs.insert(story.id)
        defer { generatingIDs.remove(story.id) }

        let comments = await fetchComments(for: story)
        if Task.isCancelled { return }

        guard let summary = await summaryService.summarize(story: story, comments: comments) else {
            if let message = await summaryService.lastErrorDescription {
                aiStatus = .failed(message)
            }
            return
        }

        summaries[story.id] = summary
        if case .failed = aiStatus {
            aiStatus = .ready
        }
    }

    func saveConfig(_ newConfig: AIProviderConfig) async {
        config = newConfig
        ConfigPersistence.save(newConfig)
        await summaryService.updateConfig(newConfig)
        await refreshAIStatus()
        if case .ready = aiStatus {
            await prefetchSummaries()
        }
    }

    func testAIConnection(
        config draft: AIProviderConfig,
        apiKey: String
    ) async -> Result<String, AIError> {
        await summaryService.testConnection(config: draft, apiKey: apiKey)
    }

    // MARK: - 阅读器

    /// 选中一条新闻：标记已读，并把正文投到阅读器。
    func select(_ story: Story) async {
        let isNewSelection = selectedStoryID != story.id
        selectedStoryID = story.id

        guard readIDs.contains(story.id) == false else {
            if isNewSelection { startArticleLoad(for: story) }
            return
        }
        readIDs.insert(story.id)
        await cache.markRead(story.id)

        if isNewSelection { startArticleLoad(for: story) }
    }

    func reloadArticle(for story: Story) async {
        startArticleLoad(for: story)
    }

    func isRead(_ story: Story) -> Bool {
        readIDs.contains(story.id)
    }

    private func startArticleLoad(for story: Story) {
        articleTask?.cancel()
        articleTask = Task { await self.loadArticle(for: story) }
    }

    private func loadArticle(for story: Story) async {
        // HN 自述帖的正文就在条目里，不需要抓取。
        if story.isSelfPost, let html = story.text, html.isEmpty == false {
            readerState = .selfPost(html: html)
            return
        }

        guard let url = story.url else {
            readerState = .degraded(.titleOnly)
            return
        }

        readerState = .loading
        let article = await extractor.extract(from: url)

        // 用户已经切到别的条目，丢弃这次结果。
        guard selectedStoryID == story.id, Task.isCancelled == false else { return }

        let level = ExtractionFallback.decide(
            ExtractionOutcome(
                articleHTML: article?.html,
                commentCount: story.commentCount ?? 0,
                externalURL: url
            )
        )

        switch level {
        case .article:
            if let article {
                readerState = .article(article)
            } else {
                readerState = .degraded(.titleAndComments)
            }
        case .titleAndComments:
            readerState = .degraded(.titleAndComments)
        case .titleOnly:
            readerState = .degraded(.titleOnly)
        }
    }

    /// 取评论树。
    ///
    /// 0.2.0 的 M0 阶段还没引入 provider 抽象，这里先按源前缀还原 HN 的数字 ID；
    /// M1 接入 `NewsSourceProvider` 后，这一步由 provider 自己负责。
    private func fetchComments(for story: Story) async -> StoryComments? {
        guard let number = HackerNewsSource.numericID(fromItemID: story.id) else { return nil }
        return try? await client.fetchStoryComments(id: number)
    }

    private static func message(for error: Error) -> String {
        if let clientError = error as? HNClientError, case .http(let status) = clientError {
            return "HN 接口返回 \(status)，稍后重试即可，缓存内容仍可阅读。"
        }
        return "网络请求失败：\((error as NSError).localizedDescription)"
    }
}
