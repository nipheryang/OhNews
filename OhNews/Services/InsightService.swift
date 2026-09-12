// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

/// 正文解读的生成。
///
/// 与 `SummaryService` 分开：那份跑在抓正文之前，只能凭标题与评论作答，作用是
/// 「值不值得点进去」；这份读正文本身，回答「讲了什么、大家怎么看」。两者输入不同、
/// 缓存键不同、错误文案也不同，混在一起只会让一边的改动牵连另一边。
///
/// 只负责「一篇正文 → 一份解读」：读配置与密钥、组装 prompt、调用接口、解析、写缓存。
/// 触发时机与并发调度由 `AppState` 负责。
actor InsightService {
    private let cache: CacheStore
    private let keychain: KeychainStore
    private let session: URLSession
    private var config: AIProviderConfig

    /// 最近一次失败的原因，供界面展示。
    private(set) var lastErrorDescription: String?

    init(
        cache: CacheStore,
        keychain: KeychainStore = KeychainStore(),
        config: AIProviderConfig = .default,
        session: URLSession = .shared
    ) {
        self.cache = cache
        self.keychain = keychain
        self.config = config
        self.session = session
    }

    func updateConfig(_ newConfig: AIProviderConfig) {
        config = newConfig
    }

    /// 解读的缓存键：正文与讨论区任一变化都要重新生成。
    ///
    /// 用 `\u{0}` 分隔两段，避免「正文尾部 + 讨论区开头」恰好拼出另一篇的组合。
    static func contentHash(articleHTML: String?, discussionHTML: String?) -> String {
        ContentHash.of("\(articleHTML ?? "")\u{0}\(discussionHTML ?? "")")
    }

    /// 读缓存里的解读（不校验有效性），供界面先显示旧内容再后台刷新。
    func cachedInsight(itemID: String) async -> ArticleInsight? {
        await cache.insight(itemID: itemID)
    }

    /// 生成一篇正文的解读。命中缓存直接返回；失败返回 nil，由界面决定提示方式。
    ///
    /// - Parameter ignoringCache: 为 true 时跳过缓存读取，用于用户主动要求重新生成。
    func insight(
        story: Story,
        articleHTML: String?,
        discussionHTML: String?,
        ignoringCache: Bool = false
    ) async -> ArticleInsight? {
        guard isConfigured() else { return nil }
        guard let endpoint = config.chatCompletionsURL() else { return nil }

        let model = config.summaryModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = InsightPromptVersion.current
        let hash = Self.contentHash(articleHTML: articleHTML, discussionHTML: discussionHTML)

        if ignoringCache == false,
           let cached = await cache.insight(
               itemID: story.id,
               contentHash: hash,
               modelName: model,
               promptVersion: version
           ) {
            return cached
        }

        let prompts = InsightPromptBuilder.build(
            story: story,
            articleHTML: articleHTML,
            discussionHTML: discussionHTML
        )
        let provider = OpenAICompatibleProvider(
            endpoint: endpoint,
            apiKey: storedKey(),
            session: session
        )

        do {
            let raw = try await provider.complete(
                AIChatRequest(
                    system: prompts.system,
                    user: prompts.user,
                    model: model,
                    usesJSONMode: true
                )
            )
            let parsed = try InsightParser.parse(raw)

            let insight = ArticleInsight(
                itemID: story.id,
                contentHash: hash,
                articleSummary: parsed.articleSummary,
                keyPoints: parsed.keyPoints,
                discussionSummary: parsed.discussionSummary,
                discussionTrends: parsed.discussionTrends,
                modelName: model,
                promptVersion: version,
                generatedAt: Date()
            )
            await cache.storeInsight(insight)
            lastErrorDescription = nil
            return insight
        } catch {
            lastErrorDescription = Self.describe(error)
            return nil
        }
    }

    /// 配置是否足以发起调用。
    func isConfigured() -> Bool {
        guard config.isEnabled, config.chatCompletionsURL() != nil else { return false }
        guard config.summaryModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else { return false }
        guard config.preset.requiresAPIKey else { return true }
        guard let key = storedKey() else { return false }
        return key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func storedKey() -> String? {
        keychain.read(account: config.preset.keychainAccount)
    }

    private static func describe(_ error: Error) -> String {
        if let aiError = error as? AIError {
            return aiError.displayMessage
        }
        if let parseError = error as? InsightParseError, parseError == .unparsable {
            return "模型返回的内容不是预期的 JSON 结构，请确认模型名是否支持结构化输出。"
        }
        return "请求失败：\((error as NSError).localizedDescription)"
    }
}
