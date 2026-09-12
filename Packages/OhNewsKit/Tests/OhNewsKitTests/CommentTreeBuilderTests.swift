// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

@Suite("CommentTreeBuilder")
struct CommentTreeBuilderTests {
    private func node(
        _ id: Int,
        author: String? = "someone",
        text: String? = "<p>正文</p>",
        createdAt: Date? = Date(timeIntervalSince1970: 1_780_000_000),
        children: [CommentNode] = []
    ) -> CommentNode {
        CommentNode(
            id: id,
            author: author,
            text: text,
            points: nil,
            createdAt: createdAt,
            children: children
        )
    }

    private func comments(_ topLevel: [CommentNode]) -> StoryComments {
        StoryComments(
            storyID: "hn:1",
            title: "标题",
            author: "op",
            points: 10,
            topLevel: topLevel
        )
    }

    /// 固定时间，避免测试依赖真实日期。
    private var fixedOptions: CommentTreeBuilder.Options {
        CommentTreeBuilder.Options(formatDate: { _ in "3 小时前" })
    }

    @Test func rendersSingleComment() {
        let result = CommentTreeBuilder.build(
            comments([node(1)]),
            options: fixedOptions
        )

        #expect(result.renderedCount == 1)
        #expect(result.omittedCount == 0)
        #expect(result.html.contains("data-depth=\"1\""))
        #expect(result.html.contains("comment-author\">someone"))
        #expect(result.html.contains("3 小时前"))
        #expect(result.html.contains("<p>正文</p>"))
    }

    @Test func numbersFloorsDepthFirst() {
        // 1 下面挂着 2、3；4 是独立顶层。深度优先应当是 1,2,3,4。
        let tree = comments([
            node(1, text: "<p>第一条</p>", children: [
                node(2, text: "<p>第二条</p>"),
                node(3, text: "<p>第三条</p>")
            ]),
            node(4, text: "<p>第四条</p>")
        ])

        let result = CommentTreeBuilder.build(tree, options: fixedOptions)

        for floor in 1...4 {
            #expect(result.html.contains("comment-floor\">\(floor)<"))
        }
        #expect(result.renderedCount == 4)
        #expect(result.html.contains("第一条"))
        #expect(result.html.contains("第四条"))
    }

    @Test func expandsOnlyTopLevelByDefault() {
        let tree = comments([node(1, children: [node(2)])])

        let result = CommentTreeBuilder.build(tree, options: fixedOptions)

        // 顶层展开、子层折叠：整份 HTML 里只应有一个 open。
        let openCount = result.html.components(separatedBy: "<details open>").count - 1
        #expect(openCount == 1)
    }

    @Test func collapsesTopLevelWhenAsked() {
        let result = CommentTreeBuilder.build(
            comments([node(1)]),
            options: CommentTreeBuilder.Options(
                expandTopLevel: false,
                formatDate: { _ in "" }
            )
        )

        #expect(result.html.contains("<details open>") == false)
        #expect(result.html.contains("<details>"))
    }

    /// 已删除的评论本身没有正文，但它的回复可能还在，不能整条跳过。
    @Test func keepsDeletedCommentWithItsReplies() {
        let tree = comments([
            node(1, text: nil, children: [node(2, text: "<p>回复还在</p>")])
        ])

        let result = CommentTreeBuilder.build(tree, options: fixedOptions)

        #expect(result.html.contains("[已删除]"))
        #expect(result.html.contains("回复还在"))
        #expect(result.renderedCount == 2)
    }

    @Test func treatsEmptyTextAsDeleted() {
        let result = CommentTreeBuilder.build(
            comments([node(1, text: "")]),
            options: fixedOptions
        )
        #expect(result.html.contains("[已删除]"))
    }

    @Test func truncatesAndReportsOmittedCount() {
        let tree = comments((1...10).map { node($0, text: "<p>第\($0)条</p>") })

        let result = CommentTreeBuilder.build(
            tree,
            options: CommentTreeBuilder.Options(
                maxComments: 4,
                formatDate: { _ in "" }
            )
        )

        #expect(result.renderedCount == 4)
        #expect(result.omittedCount == 6)
        #expect(result.html.contains("第4条"))
        #expect(result.html.contains("第5条") == false)
    }

    /// 截断按深度优先顺序生效，不能只渲染前几棵子树。
    @Test func truncatesAcrossNestedReplies() {
        let tree = comments([
            node(1, text: "<p>甲</p>", children: [
                node(2, text: "<p>乙</p>"),
                node(3, text: "<p>丙</p>")
            ]),
            node(4, text: "<p>丁</p>")
        ])

        let result = CommentTreeBuilder.build(
            tree,
            options: CommentTreeBuilder.Options(maxComments: 3, formatDate: { _ in "" })
        )

        #expect(result.renderedCount == 3)
        #expect(result.omittedCount == 1)
        #expect(result.html.contains("丙"))
        #expect(result.html.contains("丁") == false)
    }

    @Test func capsIndentDepth() {
        // 造 8 层嵌套，缩进层级不应超过 maxIndentLevel + 1。
        var deepest = node(8)
        for id in stride(from: 7, through: 1, by: -1) {
            deepest = node(id, children: [deepest])
        }

        let result = CommentTreeBuilder.build(
            comments([deepest]),
            options: CommentTreeBuilder.Options(maxIndentLevel: 3, formatDate: { _ in "" })
        )

        #expect(result.html.contains("data-depth=\"4\""))
        #expect(result.html.contains("data-depth=\"5\"") == false)
        #expect(result.renderedCount == 8)
    }

    @Test func returnsEmptyHTMLForEmptyTree() {
        let result = CommentTreeBuilder.build(comments([]), options: fixedOptions)

        #expect(result.html.isEmpty)
        #expect(result.renderedCount == 0)
        #expect(result.omittedCount == 0)
    }

    @Test func escapesAuthorName() {
        let result = CommentTreeBuilder.build(
            comments([node(1, author: "<script>&\"bad\"")]),
            options: fixedOptions
        )

        #expect(result.html.contains("<script>") == false)
        #expect(result.html.contains("&lt;script&gt;"))
        #expect(result.html.contains("&amp;"))
    }

    /// 评论是外部内容，正文里的脚本与事件属性必须被剥掉。
    @Test func sanitizesCommentBody() {
        let dirty = "<p onclick=\"steal()\">正文段落</p><script>alert(1)</script>"
        let result = CommentTreeBuilder.build(
            comments([node(1, text: dirty)]),
            options: fixedOptions
        )

        #expect(result.html.contains("<script") == false)
        #expect(result.html.contains("onclick") == false)
        #expect(result.html.contains("正文段落"))
    }

    @Test func usesInjectedDateFormat() {
        let result = CommentTreeBuilder.build(
            comments([node(1)]),
            options: CommentTreeBuilder.Options(formatDate: { _ in "刚刚" })
        )

        #expect(result.html.contains("刚刚"))
    }

    @Test func omitsTimeWhenDateIsMissing() {
        let result = CommentTreeBuilder.build(
            comments([node(1, createdAt: nil)]),
            options: fixedOptions
        )

        #expect(result.html.contains("comment-time\"></span>"))
    }
}
