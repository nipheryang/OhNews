import Foundation

public enum OpenAIChatParseError: Error, Equatable {
    case unexpectedPayload
}

/// OpenAI 兼容响应的解析。
///
/// 单独放在纯逻辑层是为了能被 `swift test` 覆盖——响应结构走样是线上最常见的一类失败。
public enum OpenAIChatResponseParser {
    public static func content(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            throw OpenAIChatParseError.unexpectedPayload
        }

        if let content = message["content"] as? String,
           content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return content
        }

        // 个别推理模型会把正文放在 reasoning_content 里，content 留空。
        if let reasoning = message["reasoning_content"] as? String,
           reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return reasoning
        }

        throw OpenAIChatParseError.unexpectedPayload
    }
}
