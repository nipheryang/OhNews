// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// HN 的正文与评论都是 HTML 片段，喂给模型前需要转成纯文本。
public enum HTMLText {
    /// 段级标签替换成换行，避免段落粘连成一句。
    private static let blockTags = [
        "</p>", "<p>", "<br>", "<br/>", "<br />", "</div>", "</li>", "<li>", "</blockquote>",
    ]

    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&#x27;": "'",
        "&#39;": "'",
        "&apos;": "'",
        "&nbsp;": " ",
        "&mdash;": "—",
        "&ndash;": "–",
        "&hellip;": "…",
        "&rsquo;": "’",
        "&lsquo;": "‘",
        "&ldquo;": "“",
        "&rdquo;": "”",
    ]

    public static func plain(from html: String) -> String {
        var text = html

        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        // 先剥标签再解码实体，否则 &lt;p&gt; 会被当成真标签删掉。
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)

        text = text.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ input: String) -> String {
        var text = input
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        return decodeNumericEntities(text)
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard input.contains("&#") else { return input }
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else { return input }

        let source = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: source.length))
        guard matches.isEmpty == false else { return input }

        var result = ""
        var cursor = 0

        for match in matches {
            let isHex = source.substring(with: match.range(at: 1)).isEmpty == false
            let digits = source.substring(with: match.range(at: 2))
            guard let value = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value)
            else { continue }

            let prefixLength = match.range.location - cursor
            if prefixLength > 0 {
                result += source.substring(with: NSRange(location: cursor, length: prefixLength))
            }
            result.append(Character(scalar))
            cursor = match.range.location + match.range.length
        }

        if cursor < source.length {
            result += source.substring(from: cursor)
        }
        return result
    }
}
