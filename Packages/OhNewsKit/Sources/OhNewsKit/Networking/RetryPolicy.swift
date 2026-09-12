// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 网络重试策略。
///
/// 只对可重试的状态码生效：`429` 与 `5xx`。其余 4xx 属于请求本身有问题，重试没有意义。
public struct RetryPolicy: Hashable, Sendable {
    public let attempts: Int
    public let delays: [Duration]

    public static let `default` = RetryPolicy(
        attempts: 3,
        delays: [.seconds(1), .seconds(3), .seconds(9)]
    )

    public init(attempts: Int, delays: [Duration]) {
        self.attempts = max(1, attempts)
        self.delays = delays
    }

    /// 是否值得重试。
    public static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    /// 第 `attempt` 次失败之后应等待的时长（`attempt` 从 1 开始计）。
    /// 已经用尽次数时返回 `nil`。
    public func delay(afterAttempt attempt: Int) -> Duration? {
        guard attempt < attempts else { return nil }
        guard delays.isEmpty == false else { return .seconds(1) }
        return delays[min(attempt - 1, delays.count - 1)]
    }
}
