// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

public enum SummaryParseError: Error, Equatable {
    /// 无法从模型输出中提取出可用的摘要。
    case unparsable
}

/// 模型输出的结构化结果。
public struct ParsedSummary: Hashable, Sendable {
    public let chineseTitle: String
    public let summary: String
    public let tags: [String]
    public let commentConsensus: String?

    public init(chineseTitle: String, summary: String, tags: [String], commentConsensus: String?) {
        self.chineseTitle = chineseTitle
        self.summary = summary
        self.tags = tags
        self.commentConsensus = commentConsensus
    }
}

/// 摘要输出解析器。
///
/// 真实模型输出常见三种脏数据：包在 Markdown 代码块里、前后有多余解释文字、
/// 字段类型与约定不一致。这里按固定顺序容错，全部有单测覆盖。
public enum SummaryParser {
    private static let titleKeys = ["title_zh", "titleZh", "chinese_title", "中文标题", "title"]
    private static let summaryKeys = ["summary", "摘要", "description", "abstract"]
    private static let tagKeys = ["tags", "tag", "标签", "topics"]
    private static let consensusKeys = [
        "comment_consensus", "commentConsensus", "comments", "consensus", "评论区共识",
    ]

    public static func parse(_ raw: String, fallbackTitle: String) throws -> ParsedSummary {
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw SummaryParseError.unparsable
        }

        let summary = firstString(in: object, keys: summaryKeys) ?? ""
        guard summary.isEmpty == false else { throw SummaryParseError.unparsable }

        let title = firstString(in: object, keys: titleKeys) ?? ""
        let consensus = firstString(in: object, keys: consensusKeys)

        return ParsedSummary(
            chineseTitle: title.isEmpty ? fallbackTitle : title,
            summary: summary,
            tags: parseTags(from: firstValue(in: object, keys: tagKeys)),
            commentConsensus: (consensus?.isEmpty == false) ? consensus : nil
        )
    }

    /// 提取第一个完整的 JSON 对象。
    ///
    /// 直接按括号配对扫描，因此代码围栏和前后解释文字都能自动跳过，
    /// 也不会被字符串值里的花括号骗到。
    static func extractJSONObject(from raw: String) -> String? {
        let characters = Array(raw)
        var start: Int?
        var depth = 0
        var inString = false
        var escaped = false

        for (index, character) in characters.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"" where depth > 0:
                inString = true
            case "{":
                depth += 1
                if start == nil { start = index }
            case "}":
                depth -= 1
                if depth == 0, let begin = start {
                    return String(characters[begin...index])
                }
                if depth < 0 {
                    depth = 0
                    start = nil
                }
            default:
                break
            }
        }

        return nil
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
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    /// 标签既可能是数组，也可能是逗号分隔的字符串。
    private static func parseTags(from value: Any?) -> [String] {
        var tags: [String] = []

        if let array = value as? [Any] {
            tags = array.compactMap { $0 as? String }
        } else if let text = value as? String {
            tags = text
                .split(whereSeparator: { ",，、/|".contains($0) })
                .map(String.init)
        }

        var seen: Set<String> = []
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false && seen.insert($0).inserted }
            .prefix(6)
            .map { $0 }
    }
}
