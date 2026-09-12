// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import OhNewsKit

enum HNSourceError: Error, Equatable {
    case unknownChannel(String)
}

/// Hacker News 的 `NewsSourceProvider` 实现：把现有 `HNClient` 收在协议之后。
///
/// 状态层与界面只认协议，所以新增来源时不需要改动它们。
actor HNSourceProvider: NewsSourceProvider {
    nonisolated let source = HackerNewsSource.source

    private let client: HNClient

    init(client: HNClient = HNClient()) {
        self.client = client
    }

    func channels() async -> [SourceChannel] {
        StoryList.allCases.map { list in
            SourceChannel(
                id: HackerNewsSource.channelID(for: list),
                sourceID: HackerNewsSource.sourceID,
                name: list.displayName
            )
        }
    }

    /// 先取榜单 ID 列表，再逐条取详情。
    ///
    /// 候选 ID 会多取一些：榜单里时常混有已删除的条目，只按目标条数取会凑不满。
    nonisolated func streamItems(
        channelID: String,
        limit: Int
    ) -> AsyncThrowingStream<Story, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let list = HackerNewsSource.list(forChannelID: channelID) else {
                        throw HNSourceError.unknownChannel(channelID)
                    }

                    let ids = try await client.fetchStoryIDs(for: list)
                    var collected = 0

                    // 榜单里时常混有已删除的条目，候选多取一些才能凑满目标条数。
                    for id in ids.prefix(limit * 2) {
                        if collected >= limit || Task.isCancelled { break }
                        guard let story = try? await client.fetchStory(id: id) else { continue }
                        continuation.yield(story)
                        collected += 1
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchComments(itemID: String) async throws -> StoryComments? {
        guard let number = HackerNewsSource.numericID(fromItemID: itemID) else { return nil }
        return try await client.fetchStoryComments(id: number)
    }
}
