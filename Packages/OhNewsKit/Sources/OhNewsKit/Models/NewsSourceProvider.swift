import Foundation

/// 一个可抓取的信息源。
///
/// app 层为每种 `SourceKind` 提供一个实现，`AppState` 只依赖这个协议。
/// 因此新增来源时，改动集中在「新写一个 provider」与「源管理界面」，
/// 状态层与列表、阅读器都不需要跟着改。
///
/// 传入的 `itemID` / `channelID` 都带源前缀（如 `hn:12345`、`hn:top`），
/// 由实现方负责剥出源内标识。
public protocol NewsSourceProvider: Sendable {
    /// 该 provider 负责的源。
    var source: NewsSource { get }

    /// 该源的频道列表。Hacker News 返回固定五个，RSS 返回自身。
    func channels() async -> [SourceChannel]

    /// 抓取某个频道的内容。
    ///
    /// 每取得一条就 `yield` 一条，调用方可以边收边上屏（HN 需要逐条请求，
    /// 全部取完再显示会让首屏多等几秒）。实现方负责处理「取不够条数」的情况，
    /// 例如跳过已删除的条目。
    ///
    /// - Parameter limit: 期望的条数上限。
    func streamItems(channelID: String, limit: Int) -> AsyncThrowingStream<Story, Error>

    /// 抓取条目对应的评论树。不支持评论的来源返回 nil。
    func fetchComments(itemID: String) async throws -> StoryComments?
}
