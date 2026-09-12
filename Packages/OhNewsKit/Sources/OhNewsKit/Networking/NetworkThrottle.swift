// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// 请求闸门：按通道限制并发数与最小请求间隔。
///
/// HN 的两套公开接口都没有官方 SLA 和明确配额，正文抓取还会打到第三方站点，
/// 因此把所有出网请求集中到这里排队，而不是在各服务里各写一套。
public actor NetworkThrottle {
    /// 请求通道。间隔与并发上限按各接口的容忍度设定。
    public enum Channel: String, CaseIterable, Hashable, Sendable {
        /// 榜单 ID 列表。
        case listIDs
        /// 单条 item 详情。
        case item
        /// Algolia 评论树。
        case comments
        /// RSS / Atom 订阅抓取。
        case rss
        /// 第三方站点正文抓取。
        case article

        var permits: Int {
            switch self {
            case .listIDs: 1
            case .item: 1
            case .comments: 2
            case .rss: 2
            case .article: 2
            }
        }

        var minimumInterval: Duration {
            switch self {
            case .listIDs: .zero
            case .item: .milliseconds(200)
            case .comments: .milliseconds(500)
            case .rss: .seconds(1)
            case .article: .seconds(1)
            }
        }
    }

    public static let shared = NetworkThrottle()

    private let clock = ContinuousClock()
    private var available: [Channel: Int] = [:]
    private var waiters: [Channel: [CheckedContinuation<Void, Never>]] = [:]
    private var lastRequest: [Channel: ContinuousClock.Instant] = [:]

    public init() {}

    /// 在指定通道内执行操作：先取得并发许可，再满足最小请求间隔。
    public func perform<T: Sendable>(
        on channel: Channel,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire(channel)
        defer { release(channel) }
        await respectInterval(channel)
        return try await operation()
    }

    private func acquire(_ channel: Channel) async {
        let free = available[channel] ?? channel.permits
        if free > 0 {
            available[channel] = free - 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters[channel, default: []].append(continuation)
        }
    }

    private func release(_ channel: Channel) {
        if var queue = waiters[channel], queue.isEmpty == false {
            let next = queue.removeFirst()
            waiters[channel] = queue
            next.resume()
            return
        }
        available[channel] = min((available[channel] ?? channel.permits) + 1, channel.permits)
    }

    private func respectInterval(_ channel: Channel) async {
        let interval = channel.minimumInterval
        guard interval > .zero else { return }
        if let last = lastRequest[channel] {
            let elapsed = last.duration(to: clock.now)
            if elapsed < interval {
                try? await Task.sleep(for: interval - elapsed)
            }
        }
        lastRequest[channel] = clock.now
    }
}
