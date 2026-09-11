import Foundation
import OhNewsKit

enum RSSSourceError: Error, Equatable {
    case missingFeedURL
    case http(status: Int)
}

/// RSS / Atom 订阅源。
///
/// 一个 feed 对应一个源、一个频道。抓取走 `NetworkThrottle.rss` 通道并复用统一的
/// 重试策略；解析与映射都是包内的纯逻辑，这里只负责取数据与抛出可读的错误。
actor RSSSourceProvider: NewsSourceProvider {
    nonisolated let source: NewsSource

    private let session: URLSession
    private let throttle: NetworkThrottle
    private let retry: RetryPolicy

    init(
        source: NewsSource,
        session: URLSession = .shared,
        throttle: NetworkThrottle = .shared,
        retry: RetryPolicy = .default
    ) {
        self.source = source
        self.session = session
        self.throttle = throttle
        self.retry = retry
    }

    func channels() async -> [SourceChannel] {
        [SourceChannel(id: source.id, sourceID: source.id, name: source.name)]
    }

    nonisolated func streamItems(
        channelID: String,
        limit: Int
    ) -> AsyncThrowingStream<Story, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = source.feedURL else {
                        throw RSSSourceError.missingFeedURL
                    }
                    let data = try await fetchData(url)
                    let feed = try FeedParser.parse(data)

                    for story in FeedItemMapper.stories(
                        from: feed,
                        source: source,
                        limit: limit
                    ) {
                        if Task.isCancelled { break }
                        continuation.yield(story)
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
        // RSS 没有评论这个概念，界面据此隐藏评论入口。
        nil
    }

    /// 抓取 feed 并返回它自己声明的标题。
    ///
    /// 添加订阅时用它验证地址是否可用，并把「用户填的地址」换成「feed 的实际标题」。
    func fetchFeedTitle() async throws -> String? {
        guard let url = source.feedURL else { throw RSSSourceError.missingFeedURL }
        let data = try await fetchData(url)
        return try FeedParser.parse(data).title
    }

    // MARK: - 传输

    private func fetchData(_ url: URL) async throws -> Data {
        var attempt = 1
        while true {
            do {
                return try await throttle.perform(on: .rss) { [session] in
                    let (data, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                        throw RSSSourceError.http(status: http.statusCode)
                    }
                    return data
                }
            } catch let error as RSSSourceError {
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
