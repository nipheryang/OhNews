// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

@Suite("ArticleSegmenter")
struct ArticleSegmenterTests {
    /// 顺序返回与片段数量等长的译文，便于断言重组结果。
    private func fakeTranslations(_ plan: ArticleSegmenter.Plan) -> [String] {
        plan.segments.map { "译\($0.index)" }
    }

    private func planAndAssemble(_ html: String) -> (plan: ArticleSegmenter.Plan, output: String?) {
        let plan = ArticleSegmenter.plan(html)
        let output = ArticleSegmenter.assemble(plan: plan, translations: fakeTranslations(plan))
        return (plan, output)
    }

    @Test func splitsSimpleParagraphs() {
        let plan = ArticleSegmenter.plan("<p>First paragraph.</p><p>Second paragraph.</p>")

        #expect(plan.segments.count == 2)
        #expect(plan.segments[0].text == "First paragraph.")
        #expect(plan.segments[1].text == "Second paragraph.")
    }

    @Test func splitsHeadingsListsAndQuotes() {
        let html = """
        <h2>A heading</h2>\
        <ul><li>An item</li></ul>\
        <blockquote>A quotation</blockquote>
        """

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.map(\.text) == ["A heading", "An item", "A quotation"])
    }

    @Test func keepsTagsWhenReassembling() {
        let html = "<h2>Title here</h2><p>Body text here.</p>"
        let (_, output) = planAndAssemble(html)

        let result = try? #require(output)
        #expect(result?.contains("<h2>译0</h2>") == true)
        #expect(result?.contains("<p>译1</p>") == true)
        #expect(result?.hasPrefix("<h2>") == true)
    }

    /// 代码块不能被翻译，也不能被正则改写。
    @Test func skipsCodeBlocks() {
        let html = "<p>Before code.</p><pre><code>let x = 1</code></pre><p>After code.</p>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.count == 2)
        let (_, output) = planAndAssemble(html)
        #expect(output?.contains("let x = 1") == true)
        #expect(output?.contains("<pre><code>") == true)
    }

    @Test func skipsTablesAndImages() {
        let html = """
        <table><tr><td>Cell text</td></tr></table>\
        <figure><img src="a.png"><figcaption>Caption text</figcaption></figure>\
        <p>Real paragraph.</p>
        """

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.map(\.text) == ["Real paragraph."])
    }

    /// 内层套着块级元素时交给内层处理，避免同一段被翻译两遍。
    @Test func skipsNestedBlocks() {
        let html = "<li><p>Nested text.</p></li>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.count == 1)
        #expect(plan.segments[0].text == "Nested text.")
    }

    @Test func skipsChineseParagraphs() {
        let html = "<p>这是一段中文，不需要翻译。</p><p>This one is English.</p>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.map(\.text) == ["This one is English."])
    }

    /// 送翻文本必须是纯文本：带标签进去，模型会把标签一并带回译文，
    /// 最终在页面上显示成可见的 `<span></span>`。
    @Test func stripsInlineTagsBeforeSending() {
        let html = "<p>See the <span class=\"x\">note</span> below.</p>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.count == 1)
        #expect(plan.segments[0].text.contains("note"))
        #expect(plan.segments[0].text.contains("<span") == false)
        #expect(plan.segments[0].text.contains("</span>") == false)
    }

    @Test func stripsInlineTagsButKeepsLinkMarkers() {
        let html = "<p>A <em>note</em> and <a href=\"https://e.com\">a link</a>.</p>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.segments.count == 2)
        #expect(plan.segments[0].text.contains("<em>") == false)
        #expect(plan.segments[0].text.contains("[[0]]"))
    }

    @Test func skipsSymbolOnlyParagraphs() {
        let plan = ArticleSegmenter.plan("<p>***</p><p>—</p><p>A real sentence.</p>")

        #expect(plan.segments.map(\.text) == ["A real sentence."])
    }

    @Test func replacesLinksWithMarkers() {
        let html = "<p>See <a href=\"https://example.com/post\">this post</a> for details.</p>"

        let plan = ArticleSegmenter.plan(html)

        // 正文一段 + 链接文字一段。
        #expect(plan.segments.count == 2)
        #expect(plan.segments[0].text == "See [[0]] for details.")
        #expect(plan.segments[0].links.count == 1)
        #expect(plan.segments[0].links[0].href == "https://example.com/post")
        #expect(plan.segments[1].text == "this post")
        #expect(plan.segments[0].links[0].labelSegmentIndex == plan.segments[1].index)
    }

    @Test func restoresLinksOnAssemble() {
        let html = "<p>See <a href=\"https://example.com/post\">this post</a> for details.</p>"
        let plan = ArticleSegmenter.plan(html)

        let output = ArticleSegmenter.assemble(plan: plan, translations: ["见 [[0]] 了解详情。", "这篇文章"])

        let result = try? #require(output)
        #expect(result == "<p>见 <a href=\"https://example.com/post\">这篇文章</a> 了解详情。</p>")
    }

    /// 译文里出现的尖括号与与号必须被转义，否则会破坏 HTML 结构。
    @Test func escapesTranslationOutput() {
        let html = "<p>A paragraph for translation.</p>"
        let plan = ArticleSegmenter.plan(html)

        let output = ArticleSegmenter.assemble(plan: plan, translations: ["小于 < 大于 > 与 & 号"])

        let result = try? #require(output)
        #expect(result?.contains("&lt;") == true)
        #expect(result?.contains("&amp;") == true)
        #expect(result?.contains("< 大于") == false)
    }

    @Test func returnsNilWhenTranslationCountMismatches() {
        let plan = ArticleSegmenter.plan("<p>One.</p><p>Two.</p>")

        #expect(ArticleSegmenter.assemble(plan: plan, translations: ["只有一条"]) == nil)
    }

    @Test func handlesEmptyDocument() {
        let plan = ArticleSegmenter.plan("")

        #expect(plan.isEmpty)
        #expect(plan.template.isEmpty)
    }

    @Test func handlesDocumentWithoutTranslatableText() {
        let html = "<pre><code>only code</code></pre>"

        let plan = ArticleSegmenter.plan(html)

        #expect(plan.isEmpty)
    }

    /// 结构必须原样保留：重组后除了文字之外，标签形状不变。
    @Test func preservesDocumentStructure() {
        let html = """
        <h2>Heading text</h2>\
        <p>First body paragraph here.</p>\
        <pre><code>code sample</code></pre>\
        <ul><li>List item text</li></ul>
        """

        let (_, output) = planAndAssemble(html)
        let result = try? #require(output)

        for tag in ["<h2>", "</h2>", "<p>", "</p>", "<pre><code>", "</code></pre>", "<ul>", "<li>", "</li>", "</ul>"] {
            #expect(result?.contains(tag) == true, "缺少标签 \(tag)")
        }
    }

    @Test func handlesUnclosedTagsWithoutCrashing() {
        let plan = ArticleSegmenter.plan("<p>Unclosed paragraph<p>Another one.</p>")

        // 不能崩，切出一条或多条都算合理。
        #expect(plan.template.isEmpty == false)
    }
}
