// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

/// 正文翻译。
///
/// 只负责「分批送翻 + 汇总重组」：分段与重组是包内的纯逻辑，模型调用复用现有的
/// OpenAI 兼容客户端。译文落盘缓存，同一条内容不会重复翻。
actor TranslationService {
    /// 每批送多少段。太大容易撞上模型输出上限，太小则请求次数变多。
    private static let batchSize = 20
    /// 同时进行的批次数。
    private static let concurrency = 3

    private let cache: CacheStore
    private let keychain = KeychainStore()
    private let session: URLSession
    private var config: AIProviderConfig

    init(
        cache: CacheStore,
        config: AIProviderConfig,
        session: URLSession = .shared
    ) {
        self.cache = cache
        self.config = config
        self.session = session
    }

    func updateConfig(_ newConfig: AIProviderConfig) {
        config = newConfig
    }

    func isConfigured() -> Bool {
        guard config.isEnabled else { return false }
        guard config.chatCompletionsURL() != nil else { return false }
        guard config.preset.requiresAPIKey == false || storedKey()?.isEmpty == false else {
            return false
        }
        return true
    }

    /// 翻译整篇正文。
    ///
    /// - Parameter onProgress: 已完成段数与总段数，供界面显示进度。
    /// - Returns: 与原文结构一致的译文 HTML。
    func translate(
        html: String,
        itemID: String,
        onProgress: @Sendable (Int, Int) -> Void
    ) async throws -> String {
        guard config.isEnabled else { throw AIError.missingAPIKey }
        guard let endpoint = config.chatCompletionsURL() else { throw AIError.invalidEndpoint }

        let model = config.summaryModel
        let version = TranslationVersion.current
        let hash = ContentHash.of(html)

        if let cached = await cache.translation(
            itemID: itemID,
            contentHash: hash,
            modelName: model,
            version: version
        ) {
            return cached.html
        }

        let plan = ArticleSegmenter.plan(html)
        // 没有可翻译的段落（例如整篇已经是中文），直接把原文当结果。
        guard plan.isEmpty == false else { return html }

        let batches = Self.makeBatches(plan.segments)
        let key = storedKey()
        var results = [String](repeating: "", count: plan.segments.count)
        var done = 0
        let total = plan.segments.count

        try await withThrowingTaskGroup(of: (offset: Int, translations: [String]).self) { group in
            var next = 0
            while next < min(Self.concurrency, batches.count) {
                let batch = batches[next]
                group.addTask { [self] in
                    let translations = try await translateBatch(
                        batch.segments,
                        endpoint: endpoint,
                        key: key,
                        model: model
                    )
                    return (batch.offset, translations)
                }
                next += 1
            }

            while let result = try await group.next() {
                for (index, text) in result.translations.enumerated() {
                    results[result.offset + index] = text
                }
                done += result.translations.count
                onProgress(done, total)

                if next < batches.count {
                    let batch = batches[next]
                    group.addTask { [self] in
                        let translations = try await translateBatch(
                            batch.segments,
                            endpoint: endpoint,
                            key: key,
                            model: model
                        )
                        return (batch.offset, translations)
                    }
                    next += 1
                }
            }
        }

        guard let translated = ArticleSegmenter.assemble(plan: plan, translations: results) else {
            throw AIError.unexpectedPayload
        }

        await cache.storeTranslation(
            ArticleTranslation(
                itemID: itemID,
                contentHash: hash,
                modelName: model,
                version: version,
                html: translated,
                generatedAt: Date()
            )
        )
        return translated
    }

    // MARK: - 内部

    private struct Batch {
        let offset: Int
        let segments: [ArticleSegmenter.Segment]
    }

    private static func makeBatches(_ segments: [ArticleSegmenter.Segment]) -> [Batch] {
        stride(from: 0, to: segments.count, by: batchSize).map { start in
            let end = min(start + batchSize, segments.count)
            return Batch(offset: start, segments: Array(segments[start..<end]))
        }
    }

    /// 翻译一批。
    ///
    /// 段数不符会让整篇译文错位，比失败更糟，所以失败后重试一次再抛错。
    private func translateBatch(
        _ segments: [ArticleSegmenter.Segment],
        endpoint: URL,
        key: String?,
        model: String
    ) async throws -> [String] {
        let request = TranslationPromptBuilder.build(segments: segments)
        let provider = OpenAICompatibleProvider(endpoint: endpoint, apiKey: key, session: session)

        var lastError: Error?
        for _ in 0..<2 {
            do {
                let raw = try await provider.complete(
                    AIChatRequest(
                        system: request.system,
                        user: request.user,
                        model: model,
                        usesJSONMode: true
                    )
                )
                return try TranslationParser.parse(raw, expectedCount: segments.count)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AIError.unexpectedPayload
    }

    private func storedKey() -> String? {
        keychain.read(account: config.preset.keychainAccount)
    }
}
