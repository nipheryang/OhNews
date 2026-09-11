import Foundation
import HeyNewsKit

enum HNClientError: Error, Equatable {
    case http(status: Int)
}

/// HN 数据的网络访问层。
///
/// 所有请求都经过 `NetworkThrottle` 排队，并对可重试的状态码做指数退避。
actor HNClient {
    private static let firebaseBase = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private static let algoliaBase = URL(string: "https://hn.algolia.com/api/v1/items")!

    private let session: URLSession
    private let throttle: NetworkThrottle
    private let retry: RetryPolicy

    init(
        session: URLSession = .shared,
        throttle: NetworkThrottle = .shared,
        retry: RetryPolicy = .default
    ) {
        self.session = session
        self.throttle = throttle
        self.retry = retry
    }

    /// 榜单 ID 列表。
    func fetchStoryIDs(for list: StoryList) async throws -> [Int] {
        let url = Self.firebaseBase.appendingPathComponent("\(list.endpointName).json")
        let data = try await fetchData(url, channel: .listIDs)
        return try HNJSONParser.parseStoryIDs(from: data)
    }

    /// 单条内容。已删除条目返回 nil。
    func fetchStory(id: Int) async throws -> Story? {
        let url = Self.firebaseBase.appendingPathComponent("item/\(id).json")
        let data = try await fetchData(url, channel: .item)
        return try HNJSONParser.parseStory(from: data)
    }

    /// 完整评论树（Algolia，一次请求返回整棵树）。
    func fetchStoryComments(id: Int) async throws -> StoryComments? {
        let url = Self.algoliaBase.appendingPathComponent("\(id)")
        let data = try await fetchData(url, channel: .comments)
        return try HNJSONParser.parseStoryComments(from: data)
    }

    // MARK: - 传输

    private func fetchData(_ url: URL, channel: NetworkThrottle.Channel) async throws -> Data {
        var attempt = 1
        while true {
            do {
                return try await throttle.perform(on: channel) { [session] in
                    let (data, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        throw HNClientError.http(status: http.statusCode)
                    }
                    return data
                }
            } catch let error as HNClientError {
                guard case .http(let status) = error,
                      RetryPolicy.isRetryable(statusCode: status),
                      let delay = retry.delay(afterAttempt: attempt)
                else {
                    throw error
                }
                try? await Task.sleep(for: delay)
                attempt += 1
            }
        }
    }
}
