// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

enum AIError: Error, Equatable {
    case invalidEndpoint
    case missingAPIKey
    case http(status: Int, message: String)
    case unexpectedPayload

    var displayMessage: String {
        switch self {
        case .invalidEndpoint:
            "接口地址无效，请在设置里检查。"
        case .missingAPIKey:
            "还没有填写 API Key。"
        case .http(let status, let message):
            message.isEmpty ? "接口返回 \(status)。" : "接口返回 \(status)：\(message)"
        case .unexpectedPayload:
            "接口返回的内容无法解析，请确认地址与模型名是否正确。"
        }
    }
}

struct AIChatRequest: Sendable {
    let system: String
    let user: String
    let model: String
    let usesJSONMode: Bool
}

/// OpenAI 兼容的对话补全客户端。
///
/// 覆盖 DeepSeek、OpenAI、Ollama 以及任何兼容该协议的端点，因此 V0 只需要这一个实现。
struct OpenAICompatibleProvider: Sendable {
    let endpoint: URL
    let apiKey: String?
    let session: URLSession

    init(endpoint: URL, apiKey: String?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    func complete(_ request: AIChatRequest) async throws -> String {
        do {
            return try await send(request, includeJSONMode: request.usesJSONMode)
        } catch let error as AIError {
            // 部分供应商不认 response_format，遇到 400 时去掉该字段再试一次。
            if request.usesJSONMode, case .http(let status, _) = error, status == 400 {
                return try await send(request, includeJSONMode: false)
            }
            throw error
        }
    }

    private func send(_ request: AIChatRequest, includeJSONMode: Bool) async throws -> String {
        var body: [String: Any] = [
            "model": request.model,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.user],
            ],
            "temperature": 0.3,
            "stream": false,
        ]
        if includeJSONMode {
            body["response_format"] = ["type": "json_object"]
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIError.unexpectedPayload }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIError.http(status: http.statusCode, message: Self.compact(raw))
        }

        do {
            return try OpenAIChatResponseParser.content(from: data)
        } catch {
            throw AIError.unexpectedPayload
        }
    }

    private static func compact(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 300 else { return trimmed }
        return String(trimmed.prefix(300)) + "…"
    }
}
