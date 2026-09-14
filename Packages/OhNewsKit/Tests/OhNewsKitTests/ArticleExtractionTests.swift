// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

struct HTMLSanitizerTests {
    @Test func removesScriptElements() {
        let html = "<p>正文</p><script>alert('x')</script><p>尾巴</p>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("正文"))
        #expect(clean.contains("尾巴"))
        #expect(clean.contains("script") == false)
        #expect(clean.contains("alert") == false)
    }

    @Test func removesScriptWithAttributesAndNewlines() {
        let html = """
        <div>前</div>
        <script type="text/javascript" async>
        var a = 1;
        console.log(a);
        </script>
        <div>后</div>
        """
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("前"))
        #expect(clean.contains("后"))
        #expect(clean.contains("console.log") == false)
    }

    @Test func removesIframeAndForm() {
        let html = "<iframe src=\"https://ads.example\"></iframe><form><input value=\"x\"></form><p>保留</p>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("iframe") == false)
        #expect(clean.contains("<form") == false)
        #expect(clean.contains("保留"))
    }

    @Test func removesEventHandlers() {
        let html = "<a href=\"https://a.com\" onclick=\"steal()\">链接</a><img src=\"x.png\" onerror='boom()'>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("onclick") == false)
        #expect(clean.contains("onerror") == false)
        #expect(clean.contains("href=\"https://a.com\""))
        #expect(clean.contains("链接"))
    }

    @Test func removesUnquotedEventHandlers() {
        let html = "<div onclick=doStuff() onload=init>内容</div>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("onclick") == false)
        #expect(clean.contains("onload") == false)
        #expect(clean.contains("内容"))
    }

    @Test func neutralisesJavascriptLinks() {
        let html = "<a href=\"javascript:void(0)\">点我</a><a href=\"javascript:alert(1)\">再来</a>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("javascript:") == false)
        #expect(clean.contains("点我"))
        #expect(clean.contains("再来"))
    }

    @Test func keepsOrdinaryMarkupIntact() {
        let html = "<h2>小标题</h2><p>段落里有 <code>inline code</code> 和 <a href=\"https://x.com\">链接</a>。</p>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean == html)
    }

    @Test func removesMetaBaseAndLink() {
        let html = "<meta http-equiv=\"refresh\" content=\"0;url=https://evil\"><base href=\"https://evil\"><link rel=\"stylesheet\" href=\"x.css\"><p>正文</p>"
        let clean = HTMLSanitizer.sanitize(html)

        #expect(clean.contains("<meta") == false)
        #expect(clean.contains("<base") == false)
        #expect(clean.contains("<link") == false)
        #expect(clean.contains("正文"))
    }
}

struct ReadabilityResultParserTests {
    private func payload(
        title: String = "标题",
        content: String = "<p>正文</p>",
        length: Int = 42
    ) -> Data {
        let json = """
        {"title":"\(title)","byline":"作者","siteName":"示例站","content":"\(content)","textContent":"正文","length":\(length)}
        """
        return Data(json.utf8)
    }

    @Test func parsesFullPayload() throws {
        let article = try #require(try ReadabilityResultParser.parse(from: payload(), sourceURL: URL(string: "https://example.com/a")))

        #expect(article.title == "标题")
        #expect(article.byline == "作者")
        #expect(article.siteName == "示例站")
        #expect(article.html == "<p>正文</p>")
        #expect(article.textLength == 42)
        #expect(article.sourceURL?.absoluteString == "https://example.com/a")
    }

    @Test func returnsNilWhenContentMissing() throws {
        let article = try ReadabilityResultParser.parse(from: payload(content: ""))
        #expect(article == nil)
    }

    @Test func returnsNilWhenContentKeyAbsent() throws {
        let article = try ReadabilityResultParser.parse(from: Data("{\"title\":\"标题\"}".utf8))
        #expect(article == nil)
    }

    @Test func treatsBlankMetadataAsNil() throws {
        let article = try #require(try ReadabilityResultParser.parse(from: payload(title: "   ")))
        #expect(article.title == nil)
    }

    @Test func throwsOnMalformedJSON() {
        #expect(throws: ReadabilityParseError.invalidPayload) {
            try ReadabilityResultParser.parse(from: Data("not json".utf8))
        }
    }
}

struct ReaderDocumentBuilderTests {
    @Test func wrapsHTMLInFullDocument() {
        let document = ReaderDocumentBuilder.build(html: "<p>正文</p>", style: "body{color:red}")

        #expect(document.hasPrefix("<!DOCTYPE html>"))
        #expect(document.contains("<meta charset=\"utf-8\">"))
        #expect(document.contains("<p>正文</p>"))
        #expect(document.contains("body{color:red}"))
    }

    @Test func injectsBaseHref() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "",
            baseURL: URL(string: "https://example.com/post?a=1&b=2")
        )

        // & 需要转义成 &amp;，否则属性值会被截断
        #expect(document.contains("<base href=\"https://example.com/post?a=1&amp;b=2\">"))
    }

    @Test func omitsBaseWhenNoURL() {
        let document = ReaderDocumentBuilder.build(html: "<p>x</p>", style: "")
        #expect(document.contains("<base") == false)
    }

    @Test func buildsFromArticle() {        let article = Article(
            title: "标题",
            byline: nil,
            siteName: nil,
            html: "<p>正文</p>",
            textLength: 2,
            sourceURL: URL(string: "https://example.com")
        )

        let document = ReaderDocumentBuilder.build(article: article, style: "p{}")
        #expect(document.contains("<p>正文</p>"))
        #expect(document.contains("https://example.com"))
    }

    @Test func omitsTopInsetByDefault() {
        let document = ReaderDocumentBuilder.build(html: "<p>x</p>", style: "p{}")
        #expect(document.contains("padding-top") == false)
    }

    @Test func injectsTopInset() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "p{}",
            topInset: 236
        )
        #expect(document.contains("body { padding-top: 236px !important; }"))
    }

    @Test func ignoresZeroTopInset() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "p{}",
            topInset: 0
        )
        #expect(document.contains("padding-top") == false)
    }

    @Test func omitsFontSizeAtDefaultScale() {
        let document = ReaderDocumentBuilder.build(html: "<p>x</p>", style: "p{}")
        #expect(document.contains("font-size") == false)
    }

    @Test func injectsFontSize() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "p{}",
            fontScale: 1.5
        )
        // 17 × 1.5 = 25.5，非整数时保留一位小数。
        #expect(document.contains("font-size: 25.5px !important"))
    }

    @Test func combinesFontSizeWithTopInsetInOneRule() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "p{}",
            topInset: 236,
            fontScale: 1.2
        )
        // 分成两条规则会互相盖掉，必须合在一条里。
        #expect(document.contains("padding-top: 236px !important"))
        #expect(document.contains("font-size: 20.4px !important"))
        #expect(document.components(separatedBy: "body {").count == 2)
    }

    @Test func writesFontSizeWithoutDecimalPointWhenWhole() {
        let document = ReaderDocumentBuilder.build(
            html: "<p>x</p>",
            style: "p{}",
            fontScale: 20.0 / ReaderPreferences.baseFontSize
        )
        #expect(document.contains("font-size: 20px !important"))
    }
}
