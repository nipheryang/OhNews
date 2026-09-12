// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

public enum ReadabilityParseError: Error, Equatable {
    case invalidPayload
}

/// 解析注入脚本返回的 Readability 结果。
///
/// 脚本约定返回 JSON 字符串；页面没有可读正文时返回空字符串，因此「解析成功但无内容」
/// 与「解析失败」是两种不同情况，前者返回 nil，后者抛错。
public enum ReadabilityResultParser {
    private struct Payload: Decodable {
        let title: String?
        let byline: String?
        let siteName: String?
        let content: String?
        let length: Int?
    }

    public static func parse(from data: Data, sourceURL: URL? = nil) throws -> Article? {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ReadabilityParseError.invalidPayload
        }

        guard let content = payload.content, content.isEmpty == false else { return nil }

        return Article(
            title: trimmed(payload.title),
            byline: trimmed(payload.byline),
            siteName: trimmed(payload.siteName),
            html: content,
            textLength: payload.length ?? 0,
            sourceURL: sourceURL
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed
    }
}
