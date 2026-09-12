// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 密钥在钥匙串里的状态。
///
/// 刻意区分「没有存」与「读不到」：应用重新签名后钥匙串授权会失效，
/// 把「读不到」说成「没有设置」会把用户引到错误的方向——他会再存一次，
/// 而问题其实在授权上。
public enum AIKeyState: Equatable, Sendable {
    case present
    case missing
    /// 条目存在但当前签名无权读取。
    case unreadable(String)
}

/// AI 配置是否真的可以发起请求。
///
/// 界面据此给出准确的提示。之前只有「能用 / 不能用」两态，于是任何原因
/// 都显示成「请设置 API Key」，用户已经设好密钥时就会觉得应用在乱说。
public enum AIConfigurationStatus: Equatable, Sendable {
    /// 用户在设置里关掉了 AI。
    case disabled
    /// 地址或模型没填全。
    case incomplete
    /// 需要密钥但钥匙串里没有。
    case keyMissing
    /// 有密钥但读不出来。
    case keyUnreadable(String)
    case ready

    public static func evaluate(
        isEnabled: Bool,
        hasEndpoint: Bool,
        hasSummaryModel: Bool,
        requiresKey: Bool,
        keyState: AIKeyState
    ) -> AIConfigurationStatus {
        guard isEnabled else { return .disabled }
        guard hasEndpoint, hasSummaryModel else { return .incomplete }
        guard requiresKey else { return .ready }

        switch keyState {
        case .present: return .ready
        case .missing: return .keyMissing
        case .unreadable(let reason): return .keyUnreadable(reason)
        }
    }

    /// 是否可以直接发起请求。
    public var canRequest: Bool { self == .ready }

    /// 面向用户的解释。`nil` 表示不需要提示。
    public var explanation: String? {
        switch self {
        case .disabled:
            nil
        case .incomplete:
            "接口地址或模型名为空，请到设置里补全。"
        case .keyMissing:
            "还没有保存 API Key。"
        case .keyUnreadable(let reason):
            reason
        case .ready:
            nil
        }
    }
}
