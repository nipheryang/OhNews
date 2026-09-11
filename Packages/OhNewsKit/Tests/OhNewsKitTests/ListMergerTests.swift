import Foundation
import Testing
@testable import OhNewsKit

@Suite("ListMerger")
struct ListMergerTests {
    private func makeStory(
        _ number: Int,
        title: String = "标题",
        score: Int? = 10,
        commentCount: Int? = 2
    ) -> Story {
        Story(
            id: HackerNewsSource.itemID(for: number),
            sourceID: HackerNewsSource.sourceID,
            title: title,
            url: URL(string: "https://example.com/\(number)"),
            score: score,
            author: "nipher",
            postedAt: Date(timeIntervalSince1970: 1_780_000_000),
            commentCount: commentCount,
            type: .story,
            text: nil
        )
    }

    @Test func keepsExistingWhenNothingFetched() {
        let existing = [makeStory(1), makeStory(2)]
        #expect(ListMerger.merge(existing: existing, fetched: [], limit: 30) == existing)
    }

    @Test func insertsNewcomersOnTop() {
        let existing = [makeStory(1), makeStory(2)]
        let fetched = [makeStory(1), makeStory(2), makeStory(3)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 30)

        // 新条目在最上面，旧条目顺序不变。
        #expect(merged.map(\.id) == [
            HackerNewsSource.itemID(for: 3),
            HackerNewsSource.itemID(for: 1),
            HackerNewsSource.itemID(for: 2)
        ])
    }

    @Test func keepsFetchedOrderAmongNewcomers() {
        let existing = [makeStory(9)]
        let fetched = [makeStory(3), makeStory(1), makeStory(2)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 30)

        #expect(merged.map(\.id) == [
            HackerNewsSource.itemID(for: 3),
            HackerNewsSource.itemID(for: 1),
            HackerNewsSource.itemID(for: 2),
            HackerNewsSource.itemID(for: 9)
        ])
    }

    /// 旧条目要在原位换成新数据：分数、评论数会变，位置不能动。
    @Test func updatesExistingInPlace() {
        let existing = [makeStory(1, score: 120, commentCount: 30), makeStory(2)]
        let fetched = [makeStory(1, score: 156, commentCount: 48)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 30)

        #expect(merged.map(\.id) == [
            HackerNewsSource.itemID(for: 1),
            HackerNewsSource.itemID(for: 2)
        ])
        #expect(merged.first?.score == 156)
        #expect(merged.first?.commentCount == 48)
    }

    @Test func trimsFromBottomWhenOverLimit() {
        let existing = [makeStory(1), makeStory(2), makeStory(3)]
        let fetched = [makeStory(4)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 2)

        #expect(merged.map(\.id) == [
            HackerNewsSource.itemID(for: 4),
            HackerNewsSource.itemID(for: 1)
        ])
    }

    /// 刷新后榜上内容完全没变时，列表应当原样返回，界面也就不会有任何动画。
    @Test func leavesListUntouchedWhenNothingChanged() {
        let existing = [makeStory(1), makeStory(2)]
        let fetched = [makeStory(1), makeStory(2)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 30)

        #expect(merged.map(\.id) == existing.map(\.id))
    }

    @Test func doesNotDuplicateWhenFetchedHasRepeatedIDs() {
        let existing = [makeStory(1)]
        let fetched = [makeStory(2), makeStory(2)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 30)

        #expect(merged.map(\.id) == [
            HackerNewsSource.itemID(for: 2),
            HackerNewsSource.itemID(for: 1)
        ])
    }

    @Test func fallsBackToExistingWhenLimitIsNotPositive() {
        let existing = [makeStory(1), makeStory(2)]
        let fetched = [makeStory(3)]

        let merged = ListMerger.merge(existing: existing, fetched: fetched, limit: 0)

        #expect(merged.count == 3)
    }
}
