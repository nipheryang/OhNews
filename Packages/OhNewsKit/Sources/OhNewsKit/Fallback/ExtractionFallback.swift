// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 阅读器的正文获取结果。
public struct ExtractionOutcome: Hashable, Sendable {
    /// 抽取到的正文 HTML。HN 自述帖直接用 `Story.text`。
    public let articleHTML: String?
    public let commentCount: Int
    public let externalURL: URL?

    public init(articleHTML: String?, commentCount: Int, externalURL: URL?) {
        self.articleHTML = articleHTML
        self.commentCount = commentCount
        self.externalURL = externalURL
    }
}

/// 阅读器以哪种形态呈现内容。
public enum ReadingLevel: String, Codable, Hashable, Sendable {
    /// 有正文可读。
    case article
    /// 没有正文，但评论区有内容。
    case titleAndComments
    /// 只有标题与链接。
    case titleOnly
}

/// 三级降级链的判定逻辑。
///
/// 抽出成纯函数是为了让「付费墙/反爬站点不会导致白屏」这条规则可以被测试覆盖，
/// 而不是散落在视图代码里靠目测确认。
public enum ExtractionFallback {
    public static func decide(_ outcome: ExtractionOutcome) -> ReadingLevel {
        if let html = outcome.articleHTML, html.isEmpty == false {
            return .article
        }
        if outcome.commentCount > 0 {
            return .titleAndComments
        }
        return .titleOnly
    }
}
