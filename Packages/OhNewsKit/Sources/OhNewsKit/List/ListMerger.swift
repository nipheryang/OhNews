import Foundation

/// 刷新时的列表合并规则。
///
/// 刷新不应该让整张列表重建——那样用户会看到内容从头往下闪一遍。
/// 这里定义的是「保留旧内容、把新内容插到顶部、已有条目原地更新」这一套规则，
/// 界面因此只有真正的新条目需要动画。
public enum ListMerger {
    /// 合并一次抓取结果。
    ///
    /// - Parameters:
    ///   - existing: 当前列表内容，顺序保持不变。
    ///   - fetched: 本次抓到的内容，顺序即来源里的顺序。
    ///   - limit: 合并后的条数上限，超出部分从底部裁掉。
    /// - Returns: 合并后的列表。
    public static func merge(existing: [Story], fetched: [Story], limit: Int) -> [Story] {
        guard fetched.isEmpty == false else { return existing }

        let latest = Dictionary(
            fetched.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingIDs = Set(existing.map(\.id))

        // 列表里没有的算新内容；同一批里靠前的排在更上面。
        // 用 seen 顺带处理同一批内部的重复，避免来源写重时列表出现两行一模一样的条目。
        var seen = existingIDs
        let newcomers = fetched.filter { story in
            guard seen.contains(story.id) == false else { return false }
            seen.insert(story.id)
            return true
        }
        // 已有的原地替换成最新数据（分数、评论数这类会变），位置不动。
        let updated = existing.map { latest[$0.id] ?? $0 }

        var merged = newcomers + updated
        if limit > 0, merged.count > limit {
            merged = Array(merged.prefix(limit))
        }
        return merged
    }
}
