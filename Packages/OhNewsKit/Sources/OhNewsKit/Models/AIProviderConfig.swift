// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation

/// AI 供应商预设。
///
/// 只描述连接方式与默认模型，不含任何密钥——密钥一律存 Keychain。
/// 界面文案由 app 层负责，不放在这里。
public enum AIProviderPreset: String, CaseIterable, Codable, Hashable, Sendable {
    case deepseek
    case openai
    case ollama
    case custom

    public var defaultBaseURL: String {
        switch self {
        case .deepseek: "https://api.deepseek.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .ollama: "http://localhost:11434/v1"
        case .custom: ""
        }
    }

    /// 摘要用的廉价档模型。
    public var defaultSummaryModel: String {
        switch self {
        case .deepseek: "deepseek-v4-flash"
        case .openai: "gpt-5-mini"
        case .ollama, .custom: ""
        }
    }

    /// 深度分析用的高配档模型（V0 尚未使用，但配置项先留好）。
    public var defaultAnalysisModel: String {
        switch self {
        case .deepseek: "deepseek-v4-pro"
        case .openai: "gpt-5"
        case .ollama, .custom: ""
        }
    }

    /// 是否需要 API Key。本地推理服务不需要。
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama: false
        case .deepseek, .openai, .custom: true
        }
    }

    /// Keychain 中的账号名。
    public var keychainAccount: String { "apikey.\(rawValue)" }
}

/// AI 接入配置。全部字段都可序列化后存进 UserDefaults，密钥不在这里。
public struct AIProviderConfig: Codable, Hashable, Sendable {
    public var preset: AIProviderPreset
    public var baseURL: String
    public var summaryModel: String
    public var analysisModel: String
    /// 关闭后完全不调用 AI，界面退回纯阅读器。
    public var isEnabled: Bool

    public init(
        preset: AIProviderPreset,
        baseURL: String,
        summaryModel: String,
        analysisModel: String,
        isEnabled: Bool
    ) {
        self.preset = preset
        self.baseURL = baseURL
        self.summaryModel = summaryModel
        self.analysisModel = analysisModel
        self.isEnabled = isEnabled
    }

    public static let `default` = AIProviderConfig(
        preset: .deepseek,
        baseURL: AIProviderPreset.deepseek.defaultBaseURL,
        summaryModel: AIProviderPreset.deepseek.defaultSummaryModel,
        analysisModel: AIProviderPreset.deepseek.defaultAnalysisModel,
        isEnabled: true
    )

    /// 套用某个预设的默认地址与模型。
    public mutating func applyPreset(_ newPreset: AIProviderPreset) {
        preset = newPreset
        baseURL = newPreset.defaultBaseURL
        summaryModel = newPreset.defaultSummaryModel
        analysisModel = newPreset.defaultAnalysisModel
    }

    /// 组装 chat/completions 端点：去掉尾部斜杠后追加路径。地址为空时返回 nil。
    public func chatCompletionsURL() -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: normalized + "/chat/completions")
    }

    /// 是否使用了明文 http 且目标不是本机/局域网地址。
    ///
    /// 本地模型服务走 http 是正常用法；公网地址用明文 http 属于配置问题，
    /// 界面需要给出提示，但不强制阻止。
    public var isInsecureTransport: Bool {
        guard let url = chatCompletionsURL(), url.scheme?.lowercased() == "http" else { return false }
        let host = url.host?.lowercased() ?? ""
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        if localHosts.contains(host) { return false }
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") || host.hasPrefix("172.16.") { return false }
        return true
    }
}
