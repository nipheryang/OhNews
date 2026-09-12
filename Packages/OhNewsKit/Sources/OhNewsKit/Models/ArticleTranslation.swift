// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// 一篇正文的译文。
///
/// 缓存有效性由「正文内容哈希 + 模型 + prompt 版本」共同决定：
/// - 内容哈希：同一条目可能先抽到摘要版正文、重抓后拿到完整版，哈希能自动作废旧译文。
/// - 模型与版本：换模型或改 prompt 后旧译文立即失效，不会与新结果混用。
public struct ArticleTranslation: Codable, Hashable, Sendable {
    public let itemID: String
    public let contentHash: String
    public let modelName: String
    public let version: String
    /// 译文正文（HTML，结构与原文一致）。
    public let html: String
    public let generatedAt: Date

    public init(
        itemID: String,
        contentHash: String,
        modelName: String,
        version: String,
        html: String,
        generatedAt: Date
    ) {
        self.itemID = itemID
        self.contentHash = contentHash
        self.modelName = modelName
        self.version = version
        self.html = html
        self.generatedAt = generatedAt
    }

    /// 这份译文是否仍然对应当前内容与配置。
    public func matches(contentHash: String, modelName: String, version: String) -> Bool {
        self.contentHash == contentHash
            && self.modelName == modelName
            && self.version == version
    }
}
