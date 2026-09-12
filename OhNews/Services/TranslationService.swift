// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

/// 一次翻译的输入。
struct TranslationParts: Sendable {
    /// 标题（纯文本）。界面上的标题不在正文文档里，所以单独送翻。
    var title: String?
    var articleHTML: String?
    var discussionHTML: String?

    var isEmpty: Bool {
        (title?.isEmpty ?? true) && (articleHTML?.isEmpty ?? true) && (discussionHTML?.isEmpty ?? true)
    }
}

/// 一次翻译的结果。
struct TranslationResult: Equatable, Sendable {
    var title: String?
    var articleHTML: String?
    var discussionHTML: String?
}

/// 正文、标题与讨论区的翻译。
///
/// 只负责「分批送翻 + 汇总重组」：分段与重组是包内的纯逻辑，模型调用复用现有的
/// OpenAI 兼容客户端。三部分共用一次批处理与一份缓存，避免同一篇文章翻两遍。
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

    /// 翻译一条内容的三个部分。
    ///
    /// - Parameter onProgress: 已完成段数与总段数，供界面显示进度。
    func translate(
        parts: TranslationParts,
        itemID: String,
        onProgress: @Sendable (Int, Int) -> Void
    ) async throws -> TranslationResult {
        guard config.isEnabled else { throw AIError.missingAPIKey }
        guard let endpoint = config.chatCompletionsURL() else { throw AIError.invalidEndpoint }

        let model = config.summaryModel
        let version = TranslationVersion.current
        let hash = Self.contentHash(of: parts)

        if let cached = await cache.translation(
            itemID: itemID,
            contentHash: hash,
            modelName: model,
            version: version
        ) {
            return TranslationResult(
                title: cached.title,
                articleHTML: cached.html,
                discussionHTML: cached.discussionHTML
            )
        }

        let sections = Self.makeSections(parts)
        guard sections.isEmpty == false else {
            // 没有可翻译的内容（例如整篇已经是中文），原样返回。
            return TranslationResult(
                title: parts.title,
                articleHTML: parts.articleHTML,
                discussionHTML: parts.discussionHTML
            )
        }

        let combined = sections.flatMap(\.plan.segments)
        let batches = Self.makeBatches(combined)
        let key = storedKey()
        var translations = [String](repeating: "", count: combined.count)
        var done = 0
        let total = combined.count

        try await withThrowingTaskGroup(of: (offset: Int, texts: [String]).self) { group in
            var next = 0
            while next < min(Self.concurrency, batches.count) {
                let batch = batches[next]
                group.addTask { [self] in
                    let texts = try await translateBatch(
                        batch.segments,
                        endpoint: endpoint,
                        key: key,
                        model: model
                    )
                    return (batch.offset, texts)
                }
                next += 1
            }

            while let result = try await group.next() {
                for (index, text) in result.texts.enumerated() {
                    translations[result.offset + index] = text
                }
                done += result.texts.count
                onProgress(done, total)

                if next < batches.count {
                    let batch = batches[next]
                    group.addTask { [self] in
                        let texts = try await translateBatch(
                            batch.segments,
                            endpoint: endpoint,
                            key: key,
                            model: model
                        )
                        return (batch.offset, texts)
                    }
                    next += 1
                }
            }
        }

        let output = Self.assemble(sections: sections, translations: translations)

        await cache.storeTranslation(
            ArticleTranslation(
                itemID: itemID,
                contentHash: hash,
                modelName: model,
                version: version,
                title: output.title,
                html: output.articleHTML ?? "",
                discussionHTML: output.discussionHTML,
                generatedAt: Date()
            )
        )
        return output
    }

    // MARK: - 分段与装配

    private enum SectionKind {
        case title
        case article
        case discussion
    }

    private struct Section {
        let kind: SectionKind
        /// 各部分的 plan 独立编号，装配时按切片取译文，互不干扰。
        let plan: ArticleSegmenter.Plan
    }

    private static func makeSections(_ parts: TranslationParts) -> [Section] {
        var sections: [Section] = []

        // 标题是纯文本，包成段落走同一套分段机制，装配后再取回纯文本。
        if let title = parts.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let plan = ArticleSegmenter.plan("<p>\(escape(title))</p>")
            if plan.isEmpty == false {
                sections.append(Section(kind: .title, plan: plan))
            }
        }
        if let html = parts.articleHTML, html.isEmpty == false {
            let plan = ArticleSegmenter.plan(html)
            if plan.isEmpty == false {
                sections.append(Section(kind: .article, plan: plan))
            }
        }
        if let html = parts.discussionHTML, html.isEmpty == false {
            let plan = ArticleSegmenter.plan(html)
            if plan.isEmpty == false {
                sections.append(Section(kind: .discussion, plan: plan))
            }
        }
        return sections
    }

    private static func assemble(
        sections: [Section],
        translations: [String]
    ) -> TranslationResult {
        var result = TranslationResult()
        var cursor = 0

        for section in sections {
            let count = section.plan.segments.count
            guard cursor + count <= translations.count else { break }
            let slice = Array(translations[cursor..<(cursor + count)])
            cursor += count

            guard let html = ArticleSegmenter.assemble(plan: section.plan, translations: slice) else {
                continue
            }
            switch section.kind {
            case .title:
                // 装配结果还包着 <p>，取回纯文本给界面标题用。
                result.title = HTMLText.plain(from: html)
            case .article:
                result.articleHTML = html
            case .discussion:
                result.discussionHTML = html
            }
        }
        return result
    }

    private static func contentHash(of parts: TranslationParts) -> String {
        // 三部分一起参与哈希：任何一部分变化都让旧译文作废。
        let combined = [
            parts.title ?? "",
            parts.articleHTML ?? "",
            parts.discussionHTML ?? ""
        ].joined(separator: "\u{1}")
        return ContentHash.of(combined)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - 批处理

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
