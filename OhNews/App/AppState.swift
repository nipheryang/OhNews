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
    /// 条目自带的正文（Ask HN、Show HN、以及不少 RSS 条目）。
    case selfPost(html: String)
    /// 没有正文，按降级级别呈现。
    case degraded(ReadingLevel)
    case failed(String)
}

/// 侧栏分组：一个信息源及其频道。
struct ChannelGroup: Identifiable, Hashable {
    let source: NewsSource
    let channels: [SourceChannel]

    var id: String { source.id }
}

/// 添加订阅时的可读错误。文案直接展示给用户，因此放在错误里一起返回。
struct SourceInputError: Error, Equatable {
    let message: String
}

/// 应用级状态。
///
/// 只有这里持有 UI 状态；取数据、缓存、AI 分别由 provider、`CacheStore`、
/// `SummaryService` 负责。摘要的并发调度放在这里，是因为它需要随列表与界面状态变化。
@MainActor
@Observable
final class AppState {
    /// 列表一次展示多少条。
    static let displayLimit = 30
    /// 列表加载后自动生成摘要的条数上限。
    static let summaryPrefetchLimit = 12
    /// 同时进行的摘要请求数。
    private static let summaryConcurrency = 3

    /// 侧栏当前选中的频道（如 `hn:top`、`rss:9a1f…`）。重启后沿用上次的选择。
    var selectedChannelID: String? {
        didSet { selectionPersistence.save(selectedChannelID) }
    }

    /// 内置源与用户添加的订阅源。
    var allSources: [NewsSource] = []
    /// 全部频道，顺序与源顺序一致。
    var channels: [SourceChannel] = []

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

    private let hackerNews: HNSourceProvider
    private let cache: CacheStore
    private let summaryService: SummaryService
    private let sourcesPersistence = SourcesPersistence()
    /// RSS 源按需创建并缓存；HN 的 provider 常驻。
    @ObservationIgnored private var rssProviders: [String: RSSSourceProvider] = [:]
    private var generatingIDs: Set<String> = []
    private var articleTask: Task<Void, Never>?
    private let selectionPersistence = SelectionPersistence()
    /// 正文抽取器要在首次使用时才创建 WKWebView，且不需要参与观察。
    @ObservationIgnored private lazy var extractor = ArticleExtractor()

    init(
        hackerNews: HNSourceProvider = HNSourceProvider(),
        cache: CacheStore = CacheStore(),
        config: AIProviderConfig = ConfigPersistence.load()
    ) {
        self.hackerNews = hackerNews
        self.cache = cache
        self.config = config
        self.summaryService = SummaryService(cache: cache, config: config)
    }

    // MARK: - 频道

    var selectedChannel: SourceChannel? {
        guard let selectedChannelID else { return nil }
        return channels.first { $0.id == selectedChannelID }
    }

    var channelGroups: [ChannelGroup] {
        allSources.compactMap { source in
            let items = channels.filter { $0.sourceID == source.id }
            return items.isEmpty ? nil : ChannelGroup(source: source, channels: items)
        }
    }

    var selectedStory: Story? {
        guard let selectedStoryID else { return nil }
        return stories.first { $0.id == selectedStoryID }
    }

    /// 启动准备：载入源列表并恢复上次选中的频道。
    func prepare() async {
        await reloadSources()

        if let restored = selectionPersistence.load() {
            selectedChannelID = restored
        }
        await ensureSelectedChannelExists()
    }

    /// 重新生成源与频道列表。
    func reloadSources() async {
        let userSources = await sourcesPersistence.all()
        allSources = [HackerNewsSource.source] + userSources

        var result: [SourceChannel] = []
        for source in allSources {
            switch source.kind {
            case .hackerNews:
                result.append(contentsOf: StoryList.allCases.map { list in
                    SourceChannel(
                        id: HackerNewsSource.channelID(for: list),
                        sourceID: source.id,
                        name: list.displayName
                    )
                })
            case .rss:
                // 一个 feed 一个频道，频道名与源名一致。
                result.append(
                    SourceChannel(id: source.id, sourceID: source.id, name: source.name)
                )
            }
        }
        channels = result
    }

    /// 切换频道：先渲染缓存，再拉网络，最后补齐 AI 摘要。
    func loadChannel(_ channelID: String) async {
        selectedStoryID = nil
        lastErrorMessage = nil
        articleTask?.cancel()
        readerState = .idle

        let cachedStories = await cache.cachedStories(
            forChannel: channelID,
            limit: Self.displayLimit
        )
        readIDs = await cache.readIDs()
        stories = cachedStories
        lastUpdatedAt = await cache.lastUpdatedAt()
        summaries = await cache.summaries(forItemIDs: cachedStories.map(\.id))

        await fetch(channelID)
        await prefetchSummaries()
    }

    /// 用户主动刷新。
    func refresh() async {
        guard let selectedChannelID else { return }
        await fetch(selectedChannelID)
        await prefetchSummaries()
    }

    /// 网络拉取。数据来源交给 provider，这里只负责上屏与落缓存。
    private func fetch(_ channelID: String) async {
        guard let channel = channels.first(where: { $0.id == channelID }),
              let provider = provider(for: channel.sourceID)
        else { return }

        isLoading = true
        defer { isLoading = false }

        var collected: [Story] = []

        do {
            for try await story in provider.streamItems(
                channelID: channelID,
                limit: Self.displayLimit
            ) {
                if Task.isCancelled { return }
                collected.append(story)
                await cache.storeStories([story])
                // 增量上屏：不必等 30 条全部取完才看到内容。
                stories = collected
            }

            await cache.storeItemIDs(collected.map(\.id), forChannel: channelID)
            readIDs = await cache.readIDs()
            summaries = await cache.summaries(forItemIDs: collected.map(\.id))
            lastUpdatedAt = await cache.lastUpdatedAt()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    private func provider(for sourceID: String) -> (any NewsSourceProvider)? {
        if sourceID == HackerNewsSource.sourceID { return hackerNews }
        if let cached = rssProviders[sourceID] { return cached }

        guard let source = allSources.first(where: { $0.id == sourceID }),
              source.kind == .rss
        else { return nil }

        let created = RSSSourceProvider(source: source)
        rssProviders[sourceID] = created
        return created
    }

    /// 删除源之后，选中的频道可能已经不存在，这时回落到 HN 首页。
    private func ensureSelectedChannelExists() async {
        if let selectedChannelID, channels.contains(where: { $0.id == selectedChannelID }) {
            return
        }
        selectedChannelID = HackerNewsSource.channelID(for: .top)
    }

    // MARK: - 订阅源管理

    /// 添加订阅源：先抓取验证，再把源自己声明的标题作为显示名。
    func addSource(feedURLText: String) async -> Result<NewsSource, SourceInputError> {
        let trimmed = feedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure(SourceInputError(message: "请填写订阅地址。"))
        }

        // 允许只填 example.com/feed，缺省按 https 补全。
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let host = url.host, host.isEmpty == false else {
            return .failure(SourceInputError(message: "这个地址看起来不对，请检查后重试。"))
        }

        let sourceID = SourceIdentifier.rssSourceID(feedURL: url)
        if allSources.contains(where: { $0.id == sourceID }) {
            return .failure(SourceInputError(message: "这个订阅已经添加过了。"))
        }

        let provisional = NewsSource(id: sourceID, kind: .rss, name: host, feedURL: url)
        var resolvedName = host
        do {
            if let title = try await RSSSourceProvider(source: provisional).fetchFeedTitle(),
               title.isEmpty == false {
                resolvedName = title
            }
        } catch {
            return .failure(SourceInputError(message: Self.message(for: error)))
        }

        let source = NewsSource(
            id: sourceID,
            kind: .rss,
            name: resolvedName,
            feedURL: url
        )
        await sourcesPersistence.upsert(source)
        rssProviders[sourceID] = RSSSourceProvider(source: source)
        await reloadSources()

        return .success(source)
    }

    func removeSource(id: String) async {
        guard id != HackerNewsSource.sourceID else { return }
        await sourcesPersistence.remove(id: id)
        rssProviders[id] = nil
        await reloadSources()
        await ensureSelectedChannelExists()
    }

    func renameSource(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let existing = allSources.first(where: { $0.id == id })
        else { return }

        var updated = existing
        updated.name = trimmed

        await sourcesPersistence.upsert(updated)
        rssProviders[id] = RSSSourceProvider(source: updated)
        await reloadSources()
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

    /// 选中一条内容：标记已读，并把正文投到阅读器。
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
        // 条目自带正文时直接呈现，不需要抓取外链。
        if let html = story.text, html.isEmpty == false, story.url == nil {
            readerState = .selfPost(html: html)
            return
        }

        guard let url = story.url else {
            guard let html = story.text, html.isEmpty == false else {
                readerState = .degraded(.titleOnly)
                return
            }
            readerState = .selfPost(html: html)
            return
        }

        readerState = .loading
        let article = await extractor.extract(from: url)

        // 用户已经切到别的内容，丢弃这次结果。
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

    /// 取评论树。按条目所属源选择 provider；不支持评论的来源返回 nil。
    private func fetchComments(for story: Story) async -> StoryComments? {
        guard let provider = provider(for: story.sourceID) else { return nil }
        return try? await provider.fetchComments(itemID: story.id)
    }

    private static func message(for error: Error) -> String {
        if let clientError = error as? HNClientError, case .http(let status) = clientError {
            return "HN 接口返回 \(status)，稍后重试即可，缓存内容仍可阅读。"
        }
        if let rssError = error as? RSSSourceError {
            switch rssError {
            case .missingFeedURL:
                return "这个订阅没有可用的地址。"
            case .http(let status):
                return "订阅地址返回 \(status)，请检查地址是否仍然有效。"
            }
        }
        if let parseError = error as? FeedParseError {
            switch parseError {
            case .malformedXML:
                return "这个地址返回的内容不是有效的 XML。"
            case .unsupportedFormat:
                return "这个地址不是 RSS / Atom 订阅源。"
            }
        }
        return "网络请求失败：\((error as NSError).localizedDescription)"
    }
}
