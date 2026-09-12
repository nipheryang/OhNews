// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

/// 顶层评论的挑选：按 HN 网页排名排序，且整个评论模块只保留前若干条。
@Suite("Top Level Comment Selection")
struct TopLevelCommentTests {
    private func node(_ id: Int, children: [CommentNode] = []) -> CommentNode {
        CommentNode(
            id: id,
            author: "u\(id)",
            text: "comment \(id)",
            points: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            children: children
        )
    }

    private func comments(_ topLevel: [CommentNode]) -> StoryComments {
        StoryComments(storyID: "hn:1", title: nil, author: nil, points: nil, topLevel: topLevel)
    }

    // MARK: - 排名顺序

    @Test("从 Firebase item 读出 kids 排名顺序")
    func parsesKidsOrder() throws {
        let json = Data(#"{"id":1,"type":"story","title":"T","kids":[3,1,2]}"#.utf8)
        #expect(try HNJSONParser.parseTopLevelOrder(from: json) == [3, 1, 2])
    }

    @Test("缺少 kids 时返回空数组")
    func missingKidsYieldsEmpty() throws {
        let json = Data(#"{"id":1,"type":"story","title":"T"}"#.utf8)
        #expect(try HNJSONParser.parseTopLevelOrder(from: json).isEmpty)
    }

    @Test("按排名重排顶层评论，未列出的保持原顺序排在后面")
    func reordersTopLevel() {
        let reordered = comments([node(1), node(2), node(3), node(4)]).orderingTopLevel(by: [3, 1])
        #expect(reordered.topLevel.map(\.id) == [3, 1, 2, 4])
    }

    @Test("空排名顺序时原样返回")
    func emptyOrderKeepsOriginal() {
        let reordered = comments([node(1), node(2)]).orderingTopLevel(by: [])
        #expect(reordered.topLevel.map(\.id) == [1, 2])
    }

    // MARK: - 总条数上限

    @Test("整个评论模块只保留前 N 条，其余计入未显示")
    func limitsTotalComments() {
        let result = CommentTreeBuilder.build(
            comments((1...25).map { node($0) }),
            options: CommentTreeBuilder.Options(maxComments: 10, formatDate: { _ in "x" })
        )
        #expect(result.renderedCount == 10)
        #expect(result.omittedCount == 15)
        #expect(result.html.contains(">10<"))
        #expect(result.html.contains(">11<") == false)
    }

    @Test("子回复占用同一个额度：靠前的讨论连同回复优先出现")
    func childrenShareTheQuota() {
        let tree = [
            node(1, children: [node(2), node(3)]),
            node(4, children: [node(5)]),
            node(6)
        ]
        let result = CommentTreeBuilder.build(
            comments(tree),
            options: CommentTreeBuilder.Options(maxComments: 4, formatDate: { _ in "x" })
        )
        #expect(result.renderedCount == 4)
        #expect(result.omittedCount == 2)
        #expect(result.html.contains(">4<"))
        #expect(result.html.contains(">5<") == false)
        #expect(result.html.contains(">6<") == false)
    }

    @Test("评论不足上限时全部显示，不计未显示")
    func fewerThanLimit() {
        let result = CommentTreeBuilder.build(
            comments([node(1), node(2), node(3)]),
            options: CommentTreeBuilder.Options(maxComments: 10, formatDate: { _ in "x" })
        )
        #expect(result.renderedCount == 3)
        #expect(result.omittedCount == 0)
    }
}
