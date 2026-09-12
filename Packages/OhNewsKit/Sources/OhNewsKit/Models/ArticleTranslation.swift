// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 一条内容的译文。
///
/// 覆盖三部分：标题、正文、讨论区。三者共用一次批处理与一份缓存——
/// 分开存会让「同一篇文章」的译文散成三条记录，失效时机也不好对齐。
///
/// 缓存有效性由「内容哈希 + 模型 + prompt 版本」共同决定：
/// - 内容哈希：三部分合并计算，正文或评论变化都会让旧译文作废。
/// - 模型与版本：换模型或改 prompt 后旧译文立即失效。
public struct ArticleTranslation: Codable, Hashable, Sendable {
    public let itemID: String
    public let contentHash: String
    public let modelName: String
    public let version: String
    /// 译文标题（纯文本）。原文没有独立标题时为 nil。
    public let title: String?
    /// 译文正文（HTML，结构与原文一致）。
    public let html: String
    /// 译文讨论区（HTML）。没有讨论区时为 nil。
    public let discussionHTML: String?
    public let generatedAt: Date

    public init(
        itemID: String,
        contentHash: String,
        modelName: String,
        version: String,
        title: String?,
        html: String,
        discussionHTML: String?,
        generatedAt: Date
    ) {
        self.itemID = itemID
        self.contentHash = contentHash
        self.modelName = modelName
        self.version = version
        self.title = title
        self.html = html
        self.discussionHTML = discussionHTML
        self.generatedAt = generatedAt
    }

    /// 这份译文是否仍然对应当前内容与配置。
    public func matches(contentHash: String, modelName: String, version: String) -> Bool {
        self.contentHash == contentHash
            && self.modelName == modelName
            && self.version == version
    }
}
