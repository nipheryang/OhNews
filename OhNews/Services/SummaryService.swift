import Foundation
import OhNewsKit

/// 摘要调度。
///
/// 只负责「一条内容 → 一份摘要」：读配置与密钥、组装 prompt、调用接口、解析、写缓存。
/// 并发与批次调度由 `AppState` 负责，这样两边的责任不会混在一起。
actor SummaryService {
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

    func currentConfig() -> AIProviderConfig {
        config
    }

    /// 配置是否足以发起调用：开关打开、地址可用、模型名非空、需要密钥时密钥存在。
    func isConfigured() -> Bool {
        guard config.isEnabled,
              config.chatCompletionsURL() != nil,
              config.summaryModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return false
        }
        guard config.preset.requiresAPIKey else { return true }
        return (storedKey()?.isEmpty == false)
    }

    /// 生成一条摘要。命中缓存直接返回；任何失败都返回 nil，由界面决定提示方式。
    func summarize(story: Story, comments: StoryComments?) async -> StorySummary? {
        guard isConfigured() else { return nil }

        let model = config.summaryModel
        if let cached = await cache.summary(
            itemID: story.id,
            promptVersion: PromptVersion.current,
            modelName: model
        ) {
            return cached
        }

        guard let endpoint = config.chatCompletionsURL() else { return nil }

        let prompts = PromptBuilder.build(story: story, comments: comments)
        let provider = OpenAICompatibleProvider(endpoint: endpoint, apiKey: storedKey(), session: session)

        do {
            let raw = try await provider.complete(
                AIChatRequest(
                    system: prompts.system,
                    user: prompts.user,
                    model: model,
                    usesJSONMode: true
                )
            )
            let parsed = try SummaryParser.parse(raw, fallbackTitle: story.title)

            let summary = StorySummary(
                storyID: story.id,
                chineseTitle: parsed.chineseTitle,
                summary: parsed.summary,
                tags: parsed.tags,
                commentConsensus: parsed.commentConsensus,
                modelName: model,
                promptVersion: PromptVersion.current,
                generatedAt: Date()
            )
            await cache.storeSummary(summary)
            lastErrorDescription = nil
            return summary
        } catch {
            lastErrorDescription = Self.describe(error)
            return nil
        }
    }

    private static func describe(_ error: Error) -> String {
        if let aiError = error as? AIError {
            return aiError.displayMessage
        }
        if let parseError = error as? SummaryParseError, parseError == .unparsable {
            return "模型返回的内容不是预期的 JSON 结构，请确认模型名是否支持结构化输出。"
        }
        return "请求失败：\((error as NSError).localizedDescription)"
    }

    /// 设置页的「测试连接」：用一条固定的极短输入跑通「地址 + 密钥 + 模型 + JSON 解析」全链路。
    func testConnection(config draft: AIProviderConfig, apiKey: String) async -> Result<String, AIError> {
        guard let endpoint = draft.chatCompletionsURL() else { return .failure(.invalidEndpoint) }
        if draft.preset.requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.missingAPIKey)
        }

        let story = Story(
            id: SourceIdentifier.itemID(sourceID: HackerNewsSource.sourceID, rawID: "0"),
            sourceID: HackerNewsSource.sourceID,
            title: "Show HN: A tiny connectivity test",
            url: URL(string: "https://example.com"),
            score: 1,
            author: "test",
            postedAt: Date(),
            commentCount: 0,
            type: .story,
            text: nil
        )
        let prompts = PromptBuilder.build(story: story, comments: nil)
        let provider = OpenAICompatibleProvider(endpoint: endpoint, apiKey: apiKey, session: session)

        do {
            let raw = try await provider.complete(
                AIChatRequest(
                    system: prompts.system,
                    user: prompts.user,
                    model: draft.summaryModel,
                    usesJSONMode: true
                )
            )
            let parsed = try SummaryParser.parse(raw, fallbackTitle: story.title)
            return .success(parsed.summary)
        } catch let error as AIError {
            return .failure(error)
        } catch {
            return .failure(.unexpectedPayload)
        }
    }

    private func storedKey() -> String? {
        keychain.read(account: config.preset.keychainAccount)
    }
}
