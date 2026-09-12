// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit
import Observation

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

/// 讨论区的加载状态。
enum CommentsState: Equatable {
    case idle
    case loading
    case ready(StoryComments)
    /// 这个来源没有评论（例如 RSS），界面不显示讨论区。
    case unavailable
    case failed(String)
}

/// 一次评论获取的结果。
///
/// 需要区分「取到了」「这个来源没有评论」和「请求失败」三种情况：
/// 前者显示讨论区，中者什么都不显示，后者才给重试入口。
private enum CommentsFetchResult {
    case fetched(StoryComments)
    case none
    case failed(Error)
}

/// 正文翻译的状态。
enum TranslationState: Equatable {
    /// 显示原文。
    case showingOriginal
    case translating(done: Int, total: Int)
    /// 显示译文（HTML，结构与原文一致）。
    case showingTranslation(String)
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
    /// 列表加载后自动生成摘要的条数上限（`.leadingItems` 档位使用）。
    static let summaryPrefetchLimit = SummaryPreferences.automaticLimit
    /// 同时进行的摘要请求数。
    private static let summaryConcurrency = 3
    /// 自动刷新间隔：4 小时。
    private static let autoRefreshInterval: Duration = .seconds(4 * 60 * 60)

    /// 列表条数上限，来自用户在设置里的选择。
    private(set) var listLimit = ListPreferences.defaultLimit

    /// AI 摘要的生成范围，来自用户在设置里的选择。
    private(set) var summaryScope: SummaryGenerationScope = .leadingItems

    /// 缓存文件占用的字节数，供设置页展示。
    private(set) var cacheSizeBytes: Int64 = 0

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

    /// AI 配置能不能用，细分到具体原因。
    private(set) var aiConfiguration: AIConfigurationStatus = .incomplete
    /// 最近一次请求失败的原因。与配置问题分开：配置问题持续存在，
    /// 请求失败是一次性的，用户可以关掉。
    private(set) var aiFailureMessage: String?

    /// 当前外观。
    private(set) var appearance: AppAppearance = .system

    var readerState: ReaderState = .idle
    var config: AIProviderConfig

    /// 讨论区的加载状态。
    private(set) var commentsState: CommentsState = .idle

    /// 正文翻译的状态。
    private(set) var translationState: TranslationState = .showingOriginal

    /// 评论缓存。同一条内容的评论会被摘要与讨论区两处需要，缓存避免取两遍。
    ///
    /// 不落盘：评论树体积大、时效性强，写进 `cache.json` 会让刚做完的
    /// 「缓存大小可见可清理」立刻失去意义。
    @ObservationIgnored private var commentsCache: [String: CommentsFetchResult] = [:]
    /// 正在进行中的评论请求，用于去重（同一内容不并发取两次）。
    @ObservationIgnored private var commentTasks: [String: Task<CommentsFetchResult, Never>] = [:]
    private static let commentsCacheLimit = 20
    private var commentsTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    private let hackerNews: HNSourceProvider
    private let cache: CacheStore
    private let summaryService: SummaryService
    private let translationService: TranslationService
    private let sourcesPersistence = SourcesPersistence()
    /// RSS 源按需创建并缓存；HN 的 provider 常驻。
    @ObservationIgnored private var rssProviders: [String: RSSSourceProvider] = [:]
    private var generatingIDs: Set<String> = []
    private var articleTask: Task<Void, Never>?
    /// 阅读器当前对应的条目。**不能**用 `selectedStoryID` 代替：
    /// 列表的选择绑定会在 `select(_:)` 之前就写好它，那样就分不清「新选择」了。
    private var articleStoryID: String?
    private let selectionPersistence = SelectionPersistence()
    private let listPreferences = ListPreferences()
    private let summaryPreferences = SummaryPreferences()
    /// 冷启动后的第一次加载会联网刷新一次；之后切换频道只用缓存。
    private var shouldRefreshOnLaunch = true
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
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
        self.translationService = TranslationService(cache: cache, config: config)
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

    /// 启动准备：载入源列表、用户偏好，并恢复上次选中的频道。
    func prepare() async {
        await reloadSources()
        listLimit = listPreferences.listLimit
        summaryScope = summaryPreferences.scope
        appearance = AppearancePreferences().appearance
        await refreshCacheSize()
        // 启动时就要算出真实的 AI 状态。之前这里是空的，`aiConfiguration`
        // 停在初始值，于是密钥配置正确也会先报一条「未启用」。
        await refreshAIStatus()

        if let restored = selectionPersistence.load() {
            selectedChannelID = restored
        }
        await ensureSelectedChannelExists()
        restartAutoRefreshTimer()
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

    /// 切换频道。
    ///
    /// 默认只读缓存：反复切标签不应该每次都打网络。只有两种情况才会抓取——
    /// 这个频道还没有任何缓存（否则会一直空白），或这是冷启动后的第一次加载。
    func loadChannel(_ channelID: String) async {
        selectedStoryID = nil
        lastErrorMessage = nil
        articleTask?.cancel()
        articleStoryID = nil
        commentsTask?.cancel()
        commentsState = .idle
        translationTask?.cancel()
        translationState = .showingOriginal
        readerState = .idle

        let cachedStories = await cache.cachedStories(forChannel: channelID, limit: listLimit)
        readIDs = await cache.readIDs()
        stories = cachedStories
        lastUpdatedAt = await cache.lastUpdatedAt()
        summaries = await cache.summaries(forItemIDs: cachedStories.map(\.id))

        let needsFetch = cachedStories.isEmpty || shouldRefreshOnLaunch
        guard needsFetch else { return }

        shouldRefreshOnLaunch = false
        await fetch(channelID, isInitial: cachedStories.isEmpty)
        await prefetchSummaries()
    }

    /// 用户主动刷新：重置自动刷新的计时，避免刚手动刷过又立刻自动刷一次。
    func refresh() async {
        guard let selectedChannelID else { return }
        restartAutoRefreshTimer()
        await fetch(selectedChannelID)
        await prefetchSummaries()
    }

    /// 用户在设置里改了列表条数：立刻按新上限调整，不够的话抓一次补齐。
    func applyListLimitChange() async {
        let updated = listPreferences.listLimit
        guard updated != listLimit else { return }
        listLimit = updated

        if stories.count > listLimit {
            stories = Array(stories.prefix(listLimit))
            if let selectedChannelID {
                await cache.storeItemIDs(stories.map(\.id), forChannel: selectedChannelID)
            }
        } else if let selectedChannelID {
            await fetch(selectedChannelID)
            await prefetchSummaries()
        }
    }

    /// 网络拉取。数据来源交给 provider，这里只负责上屏、合并与落缓存。
    ///
    /// - Parameter isInitial: 该频道还没有旧数据时边收边上屏；否则静默合并进现有列表，
    ///   让用户感觉不到刷新，但分数与评论数已经是新的。
    private func fetch(_ channelID: String, isInitial: Bool = false) async {
        guard let channel = channels.first(where: { $0.id == channelID }),
              let provider = provider(for: channel.sourceID)
        else { return }

        isLoading = true
        defer { isLoading = false }

        var fetched: [Story] = []

        do {
            for try await story in provider.streamItems(
                channelID: channelID,
                limit: listLimit
            ) {
                if Task.isCancelled { return }
                fetched.append(story)
                if isInitial {
                    // 首次加载没有旧数据可保，逐条上屏比等全部取完更快看到内容。
                    stories = fetched
                }
            }

            await cache.storeStories(fetched)
            if isInitial {
                stories = fetched
            } else {
                stories = ListMerger.merge(existing: stories, fetched: fetched, limit: listLimit)
            }
            await cache.storeItemIDs(stories.map(\.id), forChannel: channelID)

            readIDs = await cache.readIDs()
            summaries = await cache.summaries(forItemIDs: stories.map(\.id))
            lastUpdatedAt = await cache.lastUpdatedAt()
            await refreshCacheSize()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    // MARK: - 自动刷新

    /// 每 4 小时刷新一次当前频道。
    ///
    /// 用「睡满间隔再触发」而不是轮询。`Task.sleep` 走连续时钟，系统睡眠时间
    /// 照常计入，合盖过夜再打开不会漏掉这一轮。
    private func restartAutoRefreshTimer() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: Self.autoRefreshInterval)
                guard Task.isCancelled == false else { return }
                await self?.autoRefresh()
            }
        }
    }

    private func autoRefresh() async {
        guard isLoading == false, let selectedChannelID else { return }
        await fetch(selectedChannelID)
        await prefetchSummaries()
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
        aiConfiguration = await summaryService.configurationStatus()
    }

    /// 关掉一次性的请求失败提示。
    func dismissAIFailure() {
        aiFailureMessage = nil
    }

    /// 按用户选择的范围生成摘要。已有缓存的条目直接跳过。
    ///
    /// 状态刷新必须放在范围判断之前：手动模式下也要知道 AI 能不能用，
    /// 否则界面会一直显示「未启用」，而用户其实只是选择了手动生成。
    func prefetchSummaries() async {
        await refreshAIStatus()
        guard aiConfiguration.canRequest else { return }
        guard summaryScope != .manual else { return }

        let candidates: [Story]
        switch summaryScope {
        case .leadingItems:
            candidates = Array(stories.prefix(Self.summaryPrefetchLimit))
        case .allItems:
            candidates = stories
        case .manual:
            return
        }

        let pending = candidates.filter { summaries[$0.id] == nil }
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

    /// 为单条内容生成摘要。
    ///
    /// 列表只自动处理前若干条（控制 AI 调用成本），其余条目由用户在右键菜单里按需生成。
    ///
    /// - Parameter force: 为 true 时忽略已有摘要重新生成。
    func generateSummaryNow(for story: Story, force: Bool = false) async {
        guard Task.isCancelled == false else { return }

        await refreshAIStatus()
        guard aiConfiguration.canRequest else { return }

        generatingIDs.insert(story.id)
        defer { generatingIDs.remove(story.id) }

        // 重新生成时先把旧摘要撤下，让界面立刻进入“生成中”状态。
        if force {
            summaries[story.id] = nil
        }

        let comments = await commentsIfAvailable(for: story)
        if Task.isCancelled { return }

        guard let summary = await summaryService.summarize(
            story: story,
            comments: comments,
            ignoringCache: force
        ) else {
            if let message = await summaryService.lastErrorDescription {
                aiFailureMessage = message
            }
            return
        }

        summaries[story.id] = summary
        aiFailureMessage = nil
    }

    private func generateSummary(for story: Story) async {
        await generateSummaryNow(for: story)
    }

    /// 用户在设置里改了摘要范围：立即按新范围补生成。
    func applySummaryScopeChange() async {
        summaryScope = summaryPreferences.scope
        await prefetchSummaries()
    }

    // MARK: - 缓存

    var cacheSizeText: String {
        guard cacheSizeBytes > 0 else { return "无缓存" }
        return ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }

    func refreshCacheSize() async {
        cacheSizeBytes = await cache.cacheSizeInBytes()
    }

    /// 清空内容缓存。订阅配置与各项偏好不受影响。
    func clearCache() async {
        await cache.clear()
        readIDs = []
        summaries = [:]
        cacheSizeBytes = 0

        // 缓存没了，当前列表也重新来一次，避免内存与磁盘状态对不上。
        if let selectedChannelID {
            await loadChannel(selectedChannelID)
        }
        await refreshCacheSize()
    }

    func saveConfig(_ newConfig: AIProviderConfig) async {
        config = newConfig
        ConfigPersistence.save(newConfig)
        await summaryService.updateConfig(newConfig)
        await translationService.updateConfig(newConfig)
        // 换了配置，旧的一次性失败提示不再有参考价值。
        aiFailureMessage = nil
        await refreshAIStatus()
        if aiConfiguration.canRequest {
            await prefetchSummaries()
        }
    }

    // MARK: - 外观

    func setAppearance(_ newValue: AppAppearance) {
        var preferences = AppearancePreferences()
        preferences.appearance = newValue
        appearance = newValue
    }

    func testAIConnection(
        config draft: AIProviderConfig,
        apiKey: String
    ) async -> Result<String, AIError> {
        await summaryService.testConnection(config: draft, apiKey: apiKey)
    }

    // MARK: - 阅读器

    /// 选中一条内容：标记已读，并把正文投到阅读器。
    ///
    /// 「要不要抓正文」不能用 `selectedStoryID` 判断：列表的选择绑定会在本方法
    /// 之前就把它写成目标条目，于是判断永远为 false，正文永远不会开始加载。
    /// 因此单独用 `articleStoryID` 记录阅读器当前对应哪一条。
    func select(_ story: Story) async {
        let needsArticle = articleStoryID != story.id
        selectedStoryID = story.id

        guard readIDs.contains(story.id) == false else {
            if needsArticle { startArticleLoad(for: story) }
            return
        }
        readIDs.insert(story.id)
        await cache.markRead(story.id)

        if needsArticle { startArticleLoad(for: story) }
    }

    func reloadArticle(for story: Story) async {
        startArticleLoad(for: story)
    }

    func isRead(_ story: Story) -> Bool {
        readIDs.contains(story.id)
    }

    private func startArticleLoad(for story: Story) {
        articleTask?.cancel()
        articleStoryID = story.id
        articleTask = Task { await self.loadArticle(for: story) }

        // 讨论区与正文并行加载，互不阻塞。
        commentsTask?.cancel()
        commentsTask = Task { await self.loadComments(for: story) }

        // 换了内容，翻译状态回到原文。
        translationTask?.cancel()
        translationState = .showingOriginal
    }

    // MARK: - 翻译

    /// 当前可翻译的正文。只有真正拿到正文或自述帖正文时才有值。
    var translatableHTML: String? {
        switch readerState {
        case .article(let article): article.html
        case .selfPost(let html): html
        default: nil
        }
    }

    var canTranslate: Bool {
        translatableHTML != nil && config.isEnabled
    }

    /// 翻译正文；已经在显示译文时切回原文，正在翻译时取消。
    func toggleTranslation() async {
        switch translationState {
        case .showingTranslation:
            translationState = .showingOriginal
        case .translating:
            translationTask?.cancel()
            translationTask = nil
            translationState = .showingOriginal
        case .showingOriginal, .failed:
            await startTranslation()
        }
    }

    private func startTranslation() async {
        guard let story = selectedStory, let html = translatableHTML else { return }
        guard config.isEnabled else {
            translationState = .failed("需要先在设置里启用 AI 才能翻译。")
            return
        }

        translationTask?.cancel()
        translationState = .translating(done: 0, total: 0)

        let service = translationService
        let itemID = story.id

        translationTask = Task { [weak self] in
            // 开头就解包成强引用：后面要跨越 await，不能直接引用被捕获的 weak var。
            guard let self else { return }
            do {
                let translated = try await service.translate(
                    html: html,
                    itemID: itemID
                ) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, case .translating = self.translationState else { return }
                        self.translationState = .translating(done: done, total: total)
                    }
                }
                guard Task.isCancelled == false else { return }
                self.translationState = .showingTranslation(translated)
            } catch {
                guard Task.isCancelled == false else { return }
                self.translationState = .failed(Self.message(for: error))
            }
        }
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
    private func fetchCommentsResult(for story: Story) async -> CommentsFetchResult {
        if let cached = commentsCache[story.id] { return cached }
        if let inFlight = commentTasks[story.id] { return await inFlight.value }

        guard let provider = provider(for: story.sourceID) else { return .none }

        let task = Task { () -> CommentsFetchResult in
            do {
                if let comments = try await provider.fetchComments(itemID: story.id) {
                    return .fetched(comments)
                }
                return .none
            } catch {
                return .failed(error)
            }
        }
        commentTasks[story.id] = task
        let result = await task.value
        commentTasks[story.id] = nil

        storeComments(result, for: story.id)
        return result
    }

    /// 内存缓存写入。超出上限时丢掉其中一项，只求控制总量，不做精确 LRU。
    private func storeComments(_ result: CommentsFetchResult, for itemID: String) {
        commentsCache[itemID] = result
        if commentsCache.count > Self.commentsCacheLimit, let some = commentsCache.keys.first {
            commentsCache[some] = nil
        }
    }

    /// 摘要用：只关心评论内容，取不到就当没有（摘要本来就不依赖评论）。
    private func commentsIfAvailable(for story: Story) async -> StoryComments? {
        if case .fetched(let comments) = await fetchCommentsResult(for: story) {
            return comments
        }
        return nil
    }

    /// 为讨论区加载评论。
    private func loadComments(for story: Story) async {
        commentsState = .loading

        switch await fetchCommentsResult(for: story) {
        case .fetched(let comments):
            guard selectedStoryID == story.id, Task.isCancelled == false else { return }
            commentsState = comments.topLevel.isEmpty ? .unavailable : .ready(comments)
        case .none:
            guard selectedStoryID == story.id else { return }
            commentsState = .unavailable
        case .failed:
            guard selectedStoryID == story.id else { return }
            commentsState = .failed("讨论区暂时取不到，正文不受影响。")
        }
    }

    /// 手动重试讨论区。
    func retryComments() async {
        guard let story = selectedStory else { return }
        commentsCache[story.id] = nil
        await loadComments(for: story)
    }

    private static func message(for error: Error) -> String {
        if let aiError = error as? AIError {
            return aiError.displayMessage
        }
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
