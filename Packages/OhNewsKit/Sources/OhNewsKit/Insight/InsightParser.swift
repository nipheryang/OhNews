// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

public enum InsightParseError: Error, Equatable {
    /// 无法从模型输出中提取出可用的解读。
    case unparsable
}

/// 模型输出的结构化解读。
public struct ParsedInsight: Hashable, Sendable {
    public let articleSummary: String
    public let keyPoints: [String]
    public let discussionSummary: String?
    public let discussionTrends: [String]

    public init(
        articleSummary: String,
        keyPoints: [String],
        discussionSummary: String?,
        discussionTrends: [String]
    ) {
        self.articleSummary = articleSummary
        self.keyPoints = keyPoints
        self.discussionSummary = discussionSummary
        self.discussionTrends = discussionTrends
    }
}

/// 正文解读输出解析器。
///
/// 容错策略与 `SummaryParser` 一致（复用同一套 JSON 提取），字段名同样留了中英文与
/// 驼峰变体：模型偶尔会自作主张换一种写法，为此丢掉整次生成不划算。
public enum InsightParser {
    private static let summaryKeys = [
        "article_summary", "articleSummary", "summary", "正文总结", "摘要",
    ]
    private static let pointKeys = ["key_points", "keyPoints", "points", "要点", "关键要点"]
    private static let discussionKeys = [
        "discussion_summary", "discussionSummary", "comments_summary", "评论总结", "评论区总结",
    ]
    private static let trendKeys = [
        "discussion_trends", "discussionTrends", "trends", "趋势", "讨论趋势",
    ]

    public static func parse(_ raw: String) throws -> ParsedInsight {
        guard let json = SummaryParser.extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw InsightParseError.unparsable
        }

        let summary = firstString(in: object, keys: summaryKeys) ?? ""
        let points = stringList(from: firstValue(in: object, keys: pointKeys))
        let discussion = firstString(in: object, keys: discussionKeys)
        let trends = stringList(from: firstValue(in: object, keys: trendKeys))

        // 只有要点、没有总述也算可用；两者都空才是真的没拿到东西。
        guard summary.isEmpty == false || points.isEmpty == false else {
            throw InsightParseError.unparsable
        }

        return ParsedInsight(
            articleSummary: summary,
            keyPoints: points,
            discussionSummary: (discussion?.isEmpty == false) ? discussion : nil,
            discussionTrends: trends
        )
    }

    private static func firstValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            if let value = object[key] { return value }
        }
        return nil
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false { return trimmed }
            }
        }
        return nil
    }

    /// 列表项既可能是数组，也可能是换行／分号分隔的一整段文字，
    /// 也可能是编号列表（`1. xxx`）。
    static func stringList(from value: Any?) -> [String] {
        var items: [String] = []

        if let array = value as? [Any] {
            items = array.compactMap { $0 as? String }
        } else if let text = value as? String {
            items = text
                .split(whereSeparator: { $0 == "\n" || $0 == "；" })
                .map(String.init)
        }

        var seen: Set<String> = []
        return items
            .map { stripListMarker($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.isEmpty == false && seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    /// 去掉「1. 」「- 」「• 」这类行首标记，它们不该出现在界面里。
    private static func stripListMarker(_ text: String) -> String {
        var result = Substring(text)
        while let first = result.first, "-—–•*·".contains(first) {
            result = result.dropFirst()
            while let next = result.first, next == " " { result = result.dropFirst() }
            return String(result)
        }

        let digits = result.prefix { $0.isNumber }
        if digits.isEmpty == false {
            let rest = result.dropFirst(digits.count)
            if let dot = rest.first, dot == "." || dot == "、" || dot == ")" {
                let tail = rest.dropFirst()
                return String(tail.drop { $0 == " " })
            }
        }
        return String(result)
    }
}
