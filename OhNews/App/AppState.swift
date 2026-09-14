// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import AppKit
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

/// 正文解读的加载状态。
enum InsightState: Equatable {
    /// 未启用，或这条内容没有可解读的正文。
    case unavailable
    case generating
    case ready(ArticleInsight)
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
    /// 显示译文（标题、正文、讨论区三部分）。
    case showingTranslation(TranslationResult)
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
    /// 讨论区最多渲染多少条（含各层子评论，即整个评论模块的上限）。
    ///
    /// 热门帖可能有上千条评论，而评论区同时要送去翻译；全量处理既慢、
    /// 成本也高。这里只保留 HN 排名最前的若干条，其余不在模块里出现，
    /// 末尾给一个原文入口（讨论标题仍显示实际总数）。
    static let maxRenderedComments = 10
    /// 同时进行的摘要请求数。
    private static let summaryConcurrency = 3
    /// 自动刷新间隔：4 小时。
    private static let autoRefreshInterval: Duration = .seconds(4 * 60 * 60)

    /// 列表条数上限，来自用户在设置里的选择。
    private(set) var listLimit = ListPreferences.defaultLimit

    /// AI 摘要的生成范围，来自用户在设置里的选择。
    private(set) var summaryScope: SummaryGenerationScope = SummaryGenerationScope.fallback

    /// 缓存文件占用的字节数，供设置页展示。
    private(set) var cacheSizeBytes: Int64 = 0

    /// 收藏存档占用的字节数，供设置页展示。
    private(set) var archiveSizeBytes: Int64 = 0

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

    /// 正文字号倍数。
    ///
    /// 改了就直接重渲染正文（`ArticleWebView` 会因文档变化而重载），
    /// 代价是丢掉当前滚动位置，所以它适合调一次定下来。
    private(set) var readerFontScale = ReaderPreferences.defaultScale

    func setReaderFontScale(_ scale: Double) {
        guard scale != readerFontScale else { return }
        var preferences = ReaderPreferences()
        preferences.fontScale = scale
        // 用写回去的值：偏好会做范围钳制，可能与传进来的一致，也可能不一致。
        readerFontScale = preferences.fontScale
    }

    var readerState: ReaderState = .idle
    var config: AIProviderConfig

    /// 讨论区的加载状态。
    private(set) var commentsState: CommentsState = .idle

    /// 正文翻译的状态。
    private(set) var translationState: TranslationState = .showingOriginal

    /// 正文解读的状态。
    private(set) var insightState: InsightState = .unavailable

    /// 是否在打开正文后自动生成解读。
    private(set) var insightEnabled = true

    /// 可用的新版本。nil 表示没有，或还没查到，或用户已关掉这一版的提示。
    private(set) var availableUpdate: ReleaseInfo?

    /// 手动检查的结果文案，供设置页展示。自动检查不写这里。
    private(set) var updateCheckMessage: String?

    /// 正在进行的检查。
    @ObservationIgnored private var isCheckingForUpdates = false

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
    private var insightTask: Task<Void, Never>?
    /// 正在生成解读的条目。用来丢弃「生成期间用户已经切走」的结果。
    private var insightItemID: String?

    private let hackerNews: HNSourceProvider
    private let cache: CacheStore
    private let summaryService: SummaryService
    private let translationService: TranslationService
    private let insightService: InsightService
    private let updateService = UpdateService()
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
    private let insightPreferences = InsightPreferences()
    /// 可写：检查时间与「不再提示」的版本都要落盘。
    @ObservationIgnored private var updatePreferences = UpdatePreferences()
    /// 收藏与稍后读的存储。与缓存分开，缓存清空不影响这里。
    private let library = LibraryStore()
    /// 收藏夹（主动收藏的单篇）。单独一个文件，同样不受清缓存影响。
    private let savedPagesStore = SavedPagesStore()
    /// 收藏内容的离线存档。
    private let archives = ArchiveStore()
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
        self.insightService = InsightService(cache: cache, config: config)
        // 存过的字号在这里读回来。
        self.readerFontScale = ReaderPreferences().fontScale
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
        if let story = stories.first(where: { $0.id == selectedStoryID }) { return story }
        // 从中栏的收藏／稍后读列表打开的条目不在 `stories` 里，此时从中栏
        // 列表拿不到，回退到保存记录里那份快照。
        let saved = collectionItems + readLaterItems
        return saved.first { $0.id == selectedStoryID }?.story
    }

    /// 启动准备：载入源列表、用户偏好，并恢复上次选中的频道。
    func prepare() async {
        await reloadSources()
        listLimit = listPreferences.listLimit
        summaryScope = summaryPreferences.scope
        insightEnabled = insightPreferences.isEnabled
        // 版本检查放到最后，且不阻塞启动：它只是提示，没查成也不影响任何功能。
        Task { await checkForUpdatesIfNeeded() }
        appearance = AppearancePreferences().appearance
        await refreshCacheSize()
        await refreshArchiveSize()
        // 启动时就要算出真实的 AI 状态。之前这里是空的，`aiConfiguration`
        // 停在初始值，于是密钥配置正确也会先报一条「未启用」。
        await refreshAIStatus()
        await reloadLibrary()

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
            case .savedPage:
                // 收藏的单篇不是一个源，不会出现在 `allSources` 里；
                // 这里只是穷举，不应被执行。
                break
            }
        }
        channels = result
    }

    /// 保证源与频道已经载入。
    ///
    /// `allSources` / `channels` 只在 `prepare()` 里赋值一次，之后没有任何地方重建。
    /// 一旦那次初始化失效（启动被打断、异步环节出错），侧栏会永久空白，
    /// 而列表因为直接渲染缓存看起来仍然正常——用户看到的就是「一半正常一半空白」。
    /// 因此任何依赖频道的地方都先调一次这个幂等检查。
    func ensureSourcesLoaded() async {
        guard allSources.isEmpty || channels.isEmpty else { return }
        // 只在异常路径输出，便于在 Xcode 控制台里看到兜底被触发过。
        print("[OhNews] 频道数据为空，正在重建（兜底）")
        await reloadSources()
    }

    /// 切换频道。
    ///
    /// 默认只读缓存：反复切标签不应该每次都打网络。只有两种情况才会抓取——
    /// 这个频道还没有任何缓存（否则会一直空白），或这是冷启动后的第一次加载。
    func loadChannel(_ channelID: String) async {
        // 频道数据缺失时先重建：否则下面拿不到 provider，列表会停在缓存上不动。
        await ensureSourcesLoaded()

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

            // 抓取结束后再确认一次：侧栏依赖频道数据，一旦为空界面会缺一块。
            await ensureSourcesLoaded()

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
        if let selectedChannelID {
            // 收藏／稍后读不是频道，但同样是合法的侧栏选择，不能当成失效项重置。
            if LibraryEntry.matching(selectedChannelID) != nil { return }
            if channels.contains(where: { $0.id == selectedChannelID }) { return }
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
        cacheSizeBytes = await cache.cacheSizeInBytes()    }

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
        await insightService.updateConfig(newConfig)
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
        // 换内容就清掉跳转目标：那个序号只对上一篇文章有意义。
        pendingScroll = nil
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
        // 手动重新抓取必须绕过存档，否则只是把存下来的那份再读一遍，
        // 按钮等于没作用。
        startArticleLoad(for: story, ignoringArchive: true)
    }

    func isRead(_ story: Story) -> Bool {
        readIDs.contains(story.id)
    }

    private func startArticleLoad(for story: Story, ignoringArchive: Bool = false) {
        articleTask?.cancel()
        articleStoryID = story.id
        articleTask = Task { await self.loadArticle(for: story, ignoringArchive: ignoringArchive) }

        // 讨论区与正文并行加载，互不阻塞。
        commentsTask?.cancel()
        commentsTask = Task { await self.loadComments(for: story) }

        // 换了内容，翻译状态回到原文；上一份存档带进来的讨论区也要清掉。
        translationTask?.cancel()
        translationState = .showingOriginal
        latestTranslation = nil
        archivedDiscussionHTML = nil

        // 解读也跟着换。
        insightTask?.cancel()
        insightTask = nil
        insightItemID = nil
        insightState = .unavailable
    }

    // MARK: - 翻译

    /// 当前可翻译的内容。只有真正拿到正文、标题或讨论区时才非空。
    private var translatableParts: TranslationParts? {
        let article: String? = switch readerState {
        case .article(let article): article.html
        case .selfPost(let html): html
        default: nil
        }

        let parts = TranslationParts(
            title: selectedStory?.title,
            articleHTML: article,
            discussionHTML: discussionHTML(for: selectedStory)
        )
        return parts.isEmpty ? nil : parts
    }

    var canTranslate: Bool {
        config.isEnabled && translatableParts != nil
    }

    /// 讨论区 HTML。没有评论时返回 nil。
    ///
    /// 放在状态层而不是视图里：渲染与翻译要用同一份，分开生成容易出现两者不一致。
    func discussionHTML(for story: Story?) -> String? {
        guard let story,
              case .ready(let comments) = commentsState,
              comments.topLevel.isEmpty == false
        else { return nil }

        let result = CommentTreeBuilder.build(
            comments,
            options: CommentTreeBuilder.Options(
                maxComments: Self.maxRenderedComments,
                formatDate: RelativeTime.text(for:)
            )
        )

        var parts: [String] = [
            "<h2 class=\"discussion-title\">讨论 · \(comments.totalCount) 条</h2>",
            result.html
        ]
        if result.omittedCount > 0 {
            let link = HackerNewsSource.numericID(fromItemID: story.id).map {
                "<a href=\"https://news.ycombinator.com/item?id=\($0)\">在 Hacker News 上查看完整讨论</a>"
            } ?? "在 Hacker News 上查看完整讨论"
            parts.append(
                "<p class=\"discussion-omitted\">还有 \(result.omittedCount) 条未显示，\(link)。</p>"
            )
        }
        return parts.joined(separator: "\n")
    }

    /// 当前应显示的标题（译文优先）。标题可能带内联标签，显示前取纯文本。
    var displayTitle: String? {
        if case .showingTranslation(let result) = translationState,
           let title = result.title,
           title.isEmpty == false {
            return title
        }
        return selectedStory.map { HTMLText.plain(from: $0.title) }
    }

    /// 当前应显示的正文（译文优先）。
    var displayArticleHTML: String? {
        if case .showingTranslation(let result) = translationState,
           let html = result.articleHTML,
           html.isEmpty == false {
            return html
        }
        return switch readerState {
        case .article(let article): article.html
        case .selfPost(let html): html
        default: nil
        }
    }

    /// 当前应显示的讨论区（译文优先）。
    var displayDiscussionHTML: String? {
        if case .showingTranslation(let result) = translationState,
           let html = result.discussionHTML {
            return html
        }
        // 打开的是存档时，讨论区就用存下来的那份：它已经是拼好的成品，
        // 也不该为了重新拼一遍再去联网。
        if let archivedDiscussionHTML { return archivedDiscussionHTML }
        return discussionHTML(for: selectedStory)
    }

    /// 翻译正文；已经在显示译文时切回原文，正在翻译时取消。
    func toggleTranslation() async {
        switch translationState {
        case .showingTranslation:
            translationState = .showingOriginal
            // 切回原文也要把「现在看的是原文」记进存档，下次打开才一致。
            await refreshArchiveForSelected()
        case .translating:
            translationTask?.cancel()
            translationTask = nil
            translationState = .showingOriginal
        case .showingOriginal, .failed:
            await startTranslation()
        }
    }

    /// 把当前选中内容的存档刷新一遍（如果它被收藏过）。
    private func refreshArchiveForSelected() async {
        guard let story = selectedStory else { return }
        await refreshArchiveIfSaved(for: story)
    }

    private func startTranslation() async {
        guard let story = selectedStory else { return }
        guard config.isEnabled else {
            translationState = .failed("需要先在设置里启用 AI 才能翻译。")
            return
        }

        // 先进入翻译态再去等别的：讨论区可能要加载一会儿，而这段时间界面上
        // 必须已经有反馈，否则点下去像没点上。
        translationTask?.cancel()
        translationState = .translating(done: 0, total: 0)

        // 讨论区可能还在加载：等它到位再翻。否则讨论区 HTML 为空，整片评论会被漏掉，
        // 而且翻译完成后评论才到，页面上就会一直是一半译文一半原文。
        if case .loading = commentsState, let task = commentsTask {
            await task.value
        }

        guard let parts = translatableParts else {
            // 没有可翻内容（例如整篇已是中文）：退回原文态，不能停在「翻译中」。
            translationState = .showingOriginal
            return
        }

        let service = translationService
        let itemID = story.id

        translationTask = Task { [weak self] in
            // 开头就解包成强引用：后面要跨越 await，不能直接引用被捕获的 weak var。
            guard let self else { return }
            do {
                let result = try await service.translate(
                    parts: parts,
                    itemID: itemID
                ) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, case .translating = self.translationState else { return }
                        self.translationState = .translating(done: done, total: total)
                    }
                }
                guard Task.isCancelled == false else { return }
                self.latestTranslation = result
                self.translationState = .showingTranslation(result)
                // 刚翻完就落一份，免得收藏时手上没有译文。
                await self.refreshArchiveIfSaved(for: story)
            } catch {
                guard Task.isCancelled == false else { return }
                self.translationState = .failed(Self.message(for: error))
            }
        }
    }

    private func loadArticle(for story: Story, ignoringArchive: Bool = false) async {
        // 归档过的内容直接读本地存档：不联网、不等待。这同时保证正文里的
        // 段落编号（`p-<n>`）与标记高亮时一模一样，高亮的跳转与标黄不会错位。
        // 「重新抓取」显式跳过这一段。
        if ignoringArchive == false,
           let archive = await archives.archive(itemID: story.id) {
            guard selectedStoryID == story.id, Task.isCancelled == false else { return }
            applyArchivedBody(archive)
            return
        }

        // 条目自带正文时直接呈现，不需要抓取外链。
        if let html = story.text, html.isEmpty == false, story.url == nil {
            readerState = .selfPost(html: html)
            await refreshArchiveIfSaved(for: story)
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

        // 正文到了，如果这条已经被收藏、而当时只存下元数据，现在补上。
        await refreshArchiveIfSaved(for: story)
        // 正文就位，看看能不能开始生成解读。
        await generateInsightIfReady(for: story)
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
        // 存档里已经有那时的讨论区，直接用存下来的，不再联网。
        if let archive = await archives.archive(itemID: story.id) {
            guard selectedStoryID == story.id, Task.isCancelled == false else { return }
            applyArchivedDiscussion(archive)
            return
        }

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

        await refreshArchiveIfSaved(for: story)
        // 讨论区就位，看看能不能开始生成解读。
        await generateInsightIfReady(for: story)
    }

    /// 手动重试讨论区。
    func retryComments() async {
        guard let story = selectedStory else { return }
        commentsCache[story.id] = nil
        await loadComments(for: story)
    }

    // MARK: - 收藏夹

    /// 把一个网址收进收藏夹。
    ///
    /// 与添加订阅不同：这里不要求它是 feed，而是要求能抽出正文——
    /// 抽不出正文的地址收进来也没东西可读。两者失败的原因不一样，
    /// 提示文案也应当分开。
    func addSavedPage(urlText: String) async -> Result<Story, SourceInputError> {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure(SourceInputError(message: "请输入网址。"))
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host,
              host.contains(".")
        else {
            return .failure(SourceInputError(message: "这不是一个有效的网址。"))
        }

        // 用网址的哈希做 ID：同一个地址重复收藏不会变成两条。
        let prefix = SourceKind.savedPage.identifierPrefix
        let rawID = String(ContentHash.of(url.absoluteString).prefix(16))
        let storyID = "\(prefix):\(rawID)"

        if let existing = savedPages.first(where: { $0.id == storyID }) {
            return .success(existing.story)
        }

        guard let article = await extractor.extract(from: url) else {
            return .failure(SourceInputError(
                message: "这个页面取不到正文，可能需要登录，或内容由脚本生成。"
            ))
        }

        let extracted = article.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let story = Story(
            id: storyID,
            sourceID: prefix,
            title: extracted.isEmpty ? host : extracted,
            url: url,
            score: nil,
            author: host,
            postedAt: Date(),
            commentCount: nil,
            type: .story,
            text: nil
        )

        await savedPagesStore.add(SavedPage(story: story, savedAt: Date()))
        // 正文立刻存下来。信息流的缓存可以被一键清空，自己收的文章不能跟着丢。
        await archives.save(
            ArticleArchive(
                itemID: storyID,
                story: story,
                archivedAt: Date(),
                bodyKind: .article,
                article: article
            )
        )
        await reloadLibrary()
        showNotice("已收进收藏夹")
        return .success(story)
    }

    /// 从收藏夹移除，连它的正文副本一起删。
    func removeSavedPage(id: String) async {
        await savedPagesStore.remove(id: id)
        await archives.remove(itemID: id)
        await reloadLibrary()
    }

    // MARK: - 版本检查

    /// 本次运行是否已经查过版本。
    ///
    /// 不靠持久化的检查时间做这个判断：那个值要等写入生效，而 `prepare()` 可能
    /// 被 SwiftUI 调用不止一次，两次调用之间可能都读到旧值，于是发两遍请求。
    /// 这个标记是纯内存的，第一次调用就置位，之后一律跳过。
    @ObservationIgnored private var hasCheckedUpdateThisLaunch = false

    /// 启动后的自动检查。一次运行内只查一遍，且距离上次不够久就不发请求。
    func checkForUpdatesIfNeeded() async {
        guard hasCheckedUpdateThisLaunch == false else { return }
        hasCheckedUpdateThisLaunch = true
        guard updatePreferences.shouldCheck() else { return }
        await runUpdateCheck(announcingFailure: false)
    }

    /// 用户主动检查：无论结果如何都给出文案。
    func checkForUpdatesNow() async {
        await runUpdateCheck(announcingFailure: true)
    }

    private func runUpdateCheck(announcingFailure: Bool) async {
        // 同一时刻只查一次。视图重建会让 `prepare()` 再跑一遍，若每次都发请求，
        // 既浪费也可能触发对端的频率限制。
        guard isCheckingForUpdates == false else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let result = await updateService.check()
        updatePreferences.lastCheckAt = Date()

        switch result {
        case .newer(let info):
            // 用户关掉过这一版就不再重复提示，直到出现更新的版本。
            availableUpdate = updatePreferences.dismissedTag == info.tagName ? nil : info
            updateCheckMessage = "有新版本：\(info.tagName)"

        case .upToDate:
            availableUpdate = nil
            updateCheckMessage = "已是最新版本"

        case .failed(let reason):
            availableUpdate = nil
            // 自动检查失败不打扰：网络不通、仓库暂时不可达都属正常，
            // 没必要在阅读界面上提。用户手动点时才告诉他为什么没查成。
            updateCheckMessage = announcingFailure ? "检查失败：\(reason)" : nil
        }
    }

    /// 关掉更新提示。同一版本不再提示。
    func dismissUpdate() {
        if let tag = availableUpdate?.tagName {
            updatePreferences.dismissedTag = tag
        }
        availableUpdate = nil
    }

    /// 打开新版本的发布页面。
    func openUpdatePage() {
        guard let url = availableUpdate?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 正文解读

    /// 正文与讨论区都到位后自动生成解读。
    ///
    /// 两者是并行加载的，谁先到不一定，所以两边完成时都调它，由它判断现在能不能开始。
    /// `insightTask` 保证同一篇只生成一次。
    private func generateInsightIfReady(for story: Story) async {
        guard insightEnabled else { return }
        guard story.id == selectedStoryID else { return }
        guard insightTask == nil else { return }
        // 已经有了就别再跑一遍（存档带进来的解读也走这条）：
        // 即便缓存能命中，中间那次状态切换也会让界面闪一下。
        if case .ready = insightState { return }
        guard let articleHTML = insightArticleHTML else { return }
        // 讨论区还在加载就先等：这份解读有一半是讲评论的，早生成会得到一份
        // 没有讨论区的结果，之后还得再生成一次。
        guard commentsState != .loading else { return }

        startInsight(for: story, articleHTML: articleHTML, ignoringCache: false)
    }

    /// 手动重新生成，忽略缓存。
    func regenerateInsight() async {
        guard let story = selectedStory else { return }
        guard let articleHTML = insightArticleHTML else { return }
        insightTask?.cancel()
        startInsight(for: story, articleHTML: articleHTML, ignoringCache: true)
    }

    /// 用户在设置里改了开关：关掉就收起现有的解读，打开就立刻补一份。
    func applyInsightEnabledChange() async {
        insightEnabled = insightPreferences.isEnabled
        guard insightEnabled else {
            insightTask?.cancel()
            insightTask = nil
            insightItemID = nil
            insightState = .unavailable
            return
        }
        guard let story = selectedStory else { return }
        await generateInsightIfReady(for: story)
    }

    private func startInsight(for story: Story, articleHTML: String, ignoringCache: Bool) {
        insightItemID = story.id
        insightState = .generating
        let discussionHTML = insightDiscussionHTML

        insightTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.insightService.insight(
                story: story,
                articleHTML: articleHTML,
                discussionHTML: discussionHTML,
                ignoringCache: ignoringCache
            )
            await self.finishInsight(result, for: story)
        }
    }

    private func finishInsight(_ insight: ArticleInsight?, for story: Story) async {
        insightTask = nil
        // 生成期间用户切到了别的内容：丢掉这次结果，别写到新内容头上。
        guard story.id == selectedStoryID, insightItemID == story.id else { return }

        guard let insight else {
            insightState = .failed("正文解读暂时生成不了，可以稍后重试。")
            return
        }
        insightState = .ready(insight)
        // 收藏过的条目顺带更新存档，下次打开就有解读。
        await refreshArchiveIfSaved(for: story)
    }

    /// 送进解读的正文。
    ///
    /// 用原文而不是译文：解读本身就是中文，不必先翻一遍，也不依赖翻译是否完成。
    private var insightArticleHTML: String? {
        switch readerState {
        case .article(let article):
            article.html.isEmpty ? nil : article.html
        case .selfPost(let html):
            html.isEmpty ? nil : html
        default:
            nil
        }
    }

    /// 送进解读的讨论区。同样用原文。
    private var insightDiscussionHTML: String? {
        archivedDiscussionHTML ?? discussionHTML(for: selectedStory)
    }

    // MARK: - 收藏与稍后读

    /// 收藏列表，按保存时间倒序。
    private(set) var collectionItems: [SavedArticle] = []
    /// 稍后读列表，按保存时间倒序。
    private(set) var readLaterItems: [SavedArticle] = []
    /// 高亮的文段，按标记时间倒序。
    private(set) var passageItems: [SavedPassage] = []

    /// 收藏夹里的单篇，按收藏时间倒序。
    private(set) var savedPages: [SavedPage] = []

    /// 当前入口对应的单篇列表；停在别的入口或频道上时为空。
    var activeSavedPages: [SavedPage] {
        activeLibraryEntry == .savedPages ? savedPages : []
    }

    /// 侧栏当前是不是停在收藏／稍后读入口上。
    var activeLibraryEntry: LibraryEntry? {
        LibraryEntry.matching(selectedChannelID)
    }

    /// 当前入口对应的文章列表；停在频道上时不走这里。
    var activeLibraryItems: [SavedArticle] {
        switch activeLibraryEntry {
        case .collection: collectionItems
        case .readLater: readLaterItems
        // 高亮与收藏夹的内容不是 `SavedArticle`，各有自己的取法。
        case .highlight, .savedPages, .none: []
        }
    }

    func isCollected(_ story: Story) -> Bool {
        collectionItems.contains { $0.id == story.id }
    }

    func isInReadLater(_ story: Story) -> Bool {
        readLaterItems.contains { $0.id == story.id }
    }

    func passages(for story: Story) -> [SavedPassage] {
        passageItems.filter { $0.itemID == story.id }
    }

    /// 读一次存储，刷新三个列表。
    func reloadLibrary() async {
        collectionItems = await library.articles(.collection)
        readLaterItems = await library.articles(.readLater)
        passageItems = await library.allPassages()
        savedPages = await savedPagesStore.all()
        await backfillMetadataIfNeeded()
    }

    /// 给清单里缺中文信息的条目补上译文标题与摘要。
    ///
    /// 两种情况会缺：一是在这两个字段存在之前收的，二是先收藏、后翻译的。
    /// 先看清单，只有真缺的时候才去读存档，正常情况下是零开销。
    private func backfillMetadataIfNeeded() async {
        let missing = (collectionItems + readLaterItems).filter {
            $0.translatedTitle == nil || $0.summary == nil
        }
        guard missing.isEmpty == false else { return }

        var changed = false
        for item in missing {
            guard let archive = await archives.archive(itemID: item.id) else { continue }
            let title = archive.translation?.title
            let summary = archive.summary
            guard title != nil || summary != nil else { continue }
            await library.updateMetadata(itemID: item.id, translatedTitle: title, summary: summary)
            changed = true
        }
        guard changed else { return }

        // 不调 `reloadLibrary`，避免自己调自己。
        collectionItems = await library.articles(.collection)
        readLaterItems = await library.articles(.readLater)
    }

    /// 切换收藏，返回切换后是否已收藏。
    @discardableResult
    func toggleCollection(_ story: Story) async -> Bool {
        let saved = await library.toggleArticle(savedArticle(for: story), kind: .collection)
        await reloadLibrary()
        // 收藏就存一份离线副本；取消收藏连副本一起删。
        if saved {
            await archiveForSave(story)
        } else {
            await archives.remove(itemID: story.id)
        }
        return saved
    }

    /// 切换稍后读，返回切换后是否已加入。
    @discardableResult
    func toggleReadLater(_ story: Story) async -> Bool {
        let saved = await library.toggleArticle(savedArticle(for: story), kind: .readLater)
        await reloadLibrary()
        if saved {
            await archiveForSave(story)
        } else {
            await archives.remove(itemID: story.id)
        }
        return saved
    }

    /// 生成并写入存档。
    ///
    /// 正文还没就绪（例如从列表右键直接收藏）时写不出正文，先把已有材料存下；
    /// 正文与讨论区到位后会各自再刷新一次。
    private func archiveForSave(_ story: Story) async {
        // 目标不是当前打开的内容时，手上没有它的正文，先存元数据与摘要，
        // 等用户真打开它再补。
        if let archive = makeArchive(for: story) {
            await archives.save(archive)
            return
        }
        await archives.save(
            ArticleArchive(
                itemID: story.id,
                story: story,
                archivedAt: Date(),
                bodyKind: .degraded,
                degradedLevel: .titleOnly,
                summary: summaries[story.id]
            )
        )
    }

    /// 保存一段正文。返回 nil 表示不符合保存条件（空、过长、重复）。
    ///
    /// 失败时给一条提示：从右键菜单点过来的用户看不到任何列表变化，
    /// 不说明原因就和没点上一样。
    @discardableResult
    func savePassage(text: String, paragraphIndex: Int, for story: Story) async -> SavedPassage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            showNotice("没有选中文字")
            return nil
        }
        guard trimmed.count <= LibraryStore.maxPassageLength else {
            showNotice("选中的内容超过 \(LibraryStore.maxPassageLength) 字，没有高亮")
            return nil
        }

        let saved = await library.addPassage(
            SavedPassage(
                itemID: story.id,
                articleTitle: displayTitle ?? story.title,
                text: trimmed,
                paragraphIndex: paragraphIndex,
                savedAt: Date()
            )
        )
        guard let saved else {
            showNotice("这一段已经高亮过了")
            return nil
        }

        await reloadLibrary()
        showNotice("已高亮这一段")
        return saved
    }

    /// 当前文章里被高亮的段落编号，交给阅读器标黄。
    ///
    /// 编号按 DOM 顺序生成，只在一次渲染内有效；所以换了文章、或者重新渲染过
    /// 正文之后，编号会重新算。只认得下段落的那些高亮（序号为 -1 的丢掉），
    /// 宁可不高亮也不标到别的段上。
    func highlightedParagraphs(for story: Story) -> [Int] {
        passageItems
            .filter { $0.itemID == story.id && $0.paragraphIndex >= 0 }
            .map(\.paragraphIndex)
    }

    // MARK: - 轻提示

    /// 一次性的轻提示，例如「已收藏这一段」。几秒后自己消失。
    private(set) var transientNotice: String?

    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    /// 提示会替换上一条，并把计时重新开始——连续操作时不会提前消失。
    func showNotice(_ text: String) {
        transientNotice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard Task.isCancelled == false else { return }
            self?.transientNotice = nil
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        transientNotice = nil
    }

    func removePassage(id: String) async {
        await library.removePassage(id: id)
        await reloadLibrary()
    }

    /// 需要在阅读器里滚到的位置。
    ///
    /// 带上所属条目：只存段落序号的话，切到别的文章时新渲染的视图会拿到同一个
    /// 值而误跳。
    struct PendingScroll: Equatable {
        let itemID: String
        let paragraphIndex: Int
    }

    var pendingScroll: PendingScroll?

    /// 收藏存档占用的可读文本。
    var archiveSizeText: String {
        guard archiveSizeBytes > 0 else { return "无存档" }
        return ByteCountFormatter.string(fromByteCount: archiveSizeBytes, countStyle: .file)
    }

    func refreshArchiveSize() async {
        archiveSizeBytes = await archives.totalSizeInBytes()
    }

    /// 删除全部存档。收藏与稍后读的清单不动，只是下次打开要重新获取。
    func clearArchives() async {
        await archives.removeAll()
        await refreshArchiveSize()
    }

    /// 从高亮跳回原文的那一段。
    func openSavedPassage(_ passage: SavedPassage) async {
        let story = await cache.story(id: passage.itemID)
            ?? (collectionItems + readLaterItems).first { $0.id == passage.itemID }?.story
        guard let story else { return }
        // 先选中（选中会清掉上一次的跳转），再设新的目标。
        await select(story)
        // 段落编号为负说明当时没能定位到段落（例如选区跨了好几段），只打开不跳。
        guard passage.paragraphIndex >= 0 else { return }
        pendingScroll = PendingScroll(
            itemID: passage.itemID,
            paragraphIndex: passage.paragraphIndex
        )
    }

    /// 最近一次拿到的译文。
    ///
    /// 单独留一份（而不是只靠 `translationState`）：用户切回原文后，`translationState`
    /// 里就没有译文了，但收藏时那份译文仍然要一起存进去。
    private var latestTranslation: TranslationResult?

    /// 从存档读出的讨论区 HTML。
    ///
    /// 存档里的讨论区是当时拼好的成品，不再重算，也不再联网。为 nil 表示
    /// 当前内容没走存档，讨论区按常规流程取。
    private var archivedDiscussionHTML: String?

    /// 一篇内容的存档。
    ///
    /// 正文还没就绪时返回 nil（也从不会有失败态）：那种情况下仍会记下收藏，
    /// 等正文或讨论区到位后再补写。
    private func makeArchive(for story: Story) -> ArticleArchive? {
        guard story.id == articleStoryID else { return nil }

        let bodyKind: ArchivedBodyKind
        var article: Article?
        var selfPostHTML: String?
        var degradedLevel: ReadingLevel?

        switch readerState {
        case .article(let value):
            bodyKind = .article
            article = value
        case .selfPost(let html):
            bodyKind = .selfPost
            selfPostHTML = html
        case .degraded(let level):
            bodyKind = .degraded
            degradedLevel = level
        case .idle, .loading, .failed:
            return nil
        }

        let translation = latestTranslation.map {
            ArchivedTranslation(
                title: $0.title,
                articleHTML: $0.articleHTML,
                discussionHTML: $0.discussionHTML
            )
        }

        return ArticleArchive(
            itemID: story.id,
            story: story,
            archivedAt: Date(),
            bodyKind: bodyKind,
            article: article,
            selfPostHTML: selfPostHTML,
            degradedLevel: degradedLevel,
            discussionHTML: archivedDiscussionHTML ?? discussionHTML(for: story),
            translation: translation,
            showsTranslation: isShowingTranslation,
            summary: summaries[story.id],
            insight: archivedInsight
        )
    }

    /// 当前可存档的解读：只在它属于当前这篇时才有效。
    private var archivedInsight: ArticleInsight? {
        guard case .ready(let insight) = insightState,
              insight.itemID == articleStoryID
        else { return nil }
        return insight
    }

    private var isShowingTranslation: Bool {
        if case .showingTranslation = translationState { return true }
        return false
    }

    /// 内容有变化（正文抓到、讨论区到达、翻译完成）时刷新存档。
    ///
    /// 只写已经收藏或加入稍后读的条目：没存的没必要占硬盘。
    /// 清单里的中文标题与摘要也一并更新，收藏列表才能立刻显示。
    private func refreshArchiveIfSaved(for story: Story) async {
        guard isCollected(story) || isInReadLater(story) else { return }

        await library.updateMetadata(
            itemID: story.id,
            translatedTitle: story.id == articleStoryID ? latestTranslation?.title : nil,
            summary: summaries[story.id]
        )
        await reloadLibrary()

        guard let archive = makeArchive(for: story) else { return }
        await archives.save(archive)
    }

    /// 收藏时要一并写进清单的中文信息。
    ///
    /// 只有当前打开的正是这一篇时，手上才有它的译文；摘要是全局字典，随时能取。
    private func savedArticle(for story: Story) -> SavedArticle {
        SavedArticle(
            story: story,
            savedAt: Date(),
            translatedTitle: story.id == articleStoryID ? latestTranslation?.title : nil,
            summary: summaries[story.id]
        )
    }

    /// 把存档里的正文与译文恢复到界面上。讨论区不在这里恢复（见 `loadComments`）。
    private func applyArchivedBody(_ archive: ArticleArchive) {
        readerState = switch archive.bodyKind {
        case .article:
            archive.article.map { ReaderState.article($0) } ?? .degraded(.titleOnly)
        case .selfPost:
            .selfPost(html: archive.selfPostHTML ?? "")
        case .degraded:
            .degraded(archive.degradedLevel ?? .titleOnly)
        }

        if let translation = archive.translation {
            let result = TranslationResult(
                title: translation.title,
                articleHTML: translation.articleHTML,
                discussionHTML: translation.discussionHTML
            )
            latestTranslation = result
            translationState = archive.showsTranslation ? .showingTranslation(result) : .showingOriginal
        } else {
            latestTranslation = nil
            translationState = .showingOriginal
        }

        if let summary = archive.summary {
            summaries[archive.itemID] = summary
        }

        if let insight = archive.insight {
            insightState = .ready(insight)
        }
    }

    /// 把存档里的讨论区恢复到界面上。
    private func applyArchivedDiscussion(_ archive: ArticleArchive) {
        archivedDiscussionHTML = archive.discussionHTML
        // 存档里没有讨论区，说明当时这个来源就没有（或没取到），
        // 不该再联网试一次；显示什么由 `displayDiscussionHTML` 决定。
        commentsState = .unavailable
    }

    /// 从收藏／稍后读列表打开一篇文章。
    ///
    /// 缓存里可能已经没有这条（缓存可被清空），但保存记录带着完整的 `Story`，
    /// 阅读器可以按 url 重新抓正文，所以仍然读得了。
    func openSavedArticle(_ article: SavedArticle) async {
        let story = await cache.story(id: article.id) ?? article.story
        await select(story)
    }

    /// 按 ID 选中一条内容。先查中栏列表，再查收藏——两个列表共用同一条选择通道，
    /// 调用方不必自己分情况。
    func selectByID(_ id: String) async {
        if let story = stories.first(where: { $0.id == id }) {
            await select(story)
            return
        }
        let saved = collectionItems + readLaterItems
        if let article = saved.first(where: { $0.id == id }) {
            await openSavedArticle(article)
            return
        }
        if let page = savedPages.first(where: { $0.id == id }) {
            await select(page.story)
            return
        }
        if let passage = passageItems.first(where: { $0.id == id }) {
            await openSavedPassage(passage)
        }
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
