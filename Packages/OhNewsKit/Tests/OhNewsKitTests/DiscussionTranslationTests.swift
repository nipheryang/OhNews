// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

/// 讨论区送翻前的分段。
///
/// HN 的评论正文以裸文本开头、段间只用**不带闭合**的 `<p>` 分隔，而切分器靠
/// `<p>…</p>` 成对识别段落。不把段落规范化，绝大多数评论根本切不出来，
/// 表现就是「评论大部分没被翻译」。
@Suite("Discussion Segmentation")
struct DiscussionTranslationTests {
    private func node(
        id: Int,
        author: String,
        text: String,
        children: [CommentNode] = []
    ) -> CommentNode {
        CommentNode(
            id: id,
            author: author,
            text: text,
            points: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            children: children
        )
    }

    private func comments(_ topLevel: [CommentNode]) -> StoryComments {
        StoryComments(storyID: "hn:1", title: "T", author: "a", points: 1, topLevel: topLevel)
    }

    private func buildHTML(_ topLevel: [CommentNode]) -> String {
        CommentTreeBuilder.build(
            comments(topLevel),
            options: CommentTreeBuilder.Options(formatDate: { _ in "8小时前" })
        ).html
    }

    @Test("裸文本段落被包成成对的 p")
    func bareTextBecomesParagraph() {
        let html = CommentTreeBuilder.normalizeParagraphs("At least we know it wasn't written by a bot")
        #expect(html == "<p>At least we know it wasn't written by a bot</p>")
    }

    @Test("HN 的不闭合 p 被规范成成对的 p")
    func unclosedParagraphsAreNormalized() {
        let html = CommentTreeBuilder.normalizeParagraphs("first part<p>second part")
        #expect(html == "<p>first part</p><p>second part</p>")
    }

    @Test("含代码块的段落保持原样")
    func codeBlocksAreLeftAlone() {
        let raw = "<pre><code>let x = 1</code></pre>"
        #expect(CommentTreeBuilder.normalizeParagraphs(raw) == raw)
    }

    @Test("嵌套评论的每一段正文都能被切出来")
    func nestedCommentsAreAllSegmented() {
        let tree = [
            node(
                id: 1,
                author: "alice",
                text: "Parent comment text here.",
                children: [
                    node(id: 2, author: "bob", text: "Child reply text here."),
                    node(id: 3, author: "carol", text: "first paragraph<p>second paragraph")
                ]
            ),
            node(id: 4, author: "dave", text: "Another top level comment.")
        ]

        let plan = ArticleSegmenter.plan(buildHTML(tree))
        let texts = plan.segments.map(\.text)

        #expect(texts.contains { $0.contains("Parent comment text here") })
        #expect(texts.contains { $0.contains("Child reply text here") })
        #expect(texts.contains { $0.contains("first paragraph") })
        #expect(texts.contains { $0.contains("second paragraph") })
        #expect(texts.contains { $0.contains("Another top level comment") })
    }

    @Test("楼层号、作者与时间不会被当成正文送翻")
    func commentHeadIsNeverSentToTranslation() {
        let tree = [
            node(id: 1, author: "alice", text: "Only a plain comment.", children: [
                node(id: 2, author: "bob", text: "Child comment.")
            ])
        ]

        let plan = ArticleSegmenter.plan(buildHTML(tree))
        for segment in plan.segments {
            #expect(segment.text.contains("alice") == false)
            #expect(segment.text.contains("bob") == false)
            #expect(segment.text.contains("8小时前") == false)
        }
    }
}
