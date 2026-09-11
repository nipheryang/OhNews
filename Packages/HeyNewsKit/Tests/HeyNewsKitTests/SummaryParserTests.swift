import Foundation
import Testing
@testable import HeyNewsKit

struct SummaryParserTests {
    @Test func parsesCleanJSON() throws {
        let raw = """
        {"title_zh": "展示 HN：我的项目", "summary": "一个用来打码的工具。", "tags": ["开源", "开发工具"], "comment_consensus": "评论普遍认可实现方式。"}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "Show HN: My project")

        #expect(parsed.chineseTitle == "展示 HN：我的项目")
        #expect(parsed.summary == "一个用来打码的工具。")
        #expect(parsed.tags == ["开源", "开发工具"])
        #expect(parsed.commentConsensus == "评论普遍认可实现方式。")
    }

    @Test func parsesFencedJSON() throws {
        let raw = """
        ```json
        {"title_zh": "标题", "summary": "摘要内容。", "tags": [], "comment_consensus": ""}
        ```
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.chineseTitle == "标题")
        #expect(parsed.summary == "摘要内容。")
        #expect(parsed.tags.isEmpty)
        #expect(parsed.commentConsensus == nil)
    }

    @Test func skipsSurroundingProse() throws {
        let raw = """
        好的，我来分析这条内容：
        {"title_zh": "标题", "summary": "摘要。", "tags": ["AI"], "comment_consensus": "有分歧。"}
        希望这个结果对你有帮助。
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.summary == "摘要。")
        #expect(parsed.tags == ["AI"])
    }

    @Test func toleratesBracesInsideStringValues() throws {
        let raw = """
        {"title_zh": "标题", "summary": "代码里写成 {a: 1} 这种形式。", "tags": [], "comment_consensus": ""}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.summary == "代码里写成 {a: 1} 这种形式。")
    }

    @Test func fallsBackToOriginalTitle() throws {
        let raw = """
        {"summary": "只有摘要没有标题。", "tags": []}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "Original English Title")

        #expect(parsed.chineseTitle == "Original English Title")
    }

    @Test func acceptsTagsAsDelimitedString() throws {
        let raw = """
        {"title_zh": "标题", "summary": "摘要。", "tags": "AI, 后端、开源"}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.tags == ["AI", "后端", "开源"])
    }

    @Test func deduplicatesAndLimitsTags() throws {
        let raw = """
        {"title_zh": "标题", "summary": "摘要。", "tags": ["AI", "AI", "后端", "前端", "安全", "硬件", "科学", "文化"]}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.tags.count == 6)
        #expect(parsed.tags.first == "AI")
    }

    @Test func ignoresNonStringTagEntries() throws {
        let raw = """
        {"title_zh": "标题", "summary": "摘要。", "tags": ["AI", 42, null, "后端"]}
        """

        let parsed = try SummaryParser.parse(raw, fallbackTitle: "fallback")

        #expect(parsed.tags == ["AI", "后端"])
    }

    @Test func throwsWhenSummaryMissing() {
        let raw = """
        {"title_zh": "标题", "tags": ["AI"]}
        """

        #expect(throws: SummaryParseError.unparsable) {
            try SummaryParser.parse(raw, fallbackTitle: "fallback")
        }
    }

    @Test func throwsWhenNoJSONObject() {
        #expect(throws: SummaryParseError.unparsable) {
            try SummaryParser.parse("抱歉，我无法完成这个请求。", fallbackTitle: "fallback")
        }
    }

    @Test func throwsWhenJSONIsTruncated() {
        let raw = """
        {"title_zh": "标题", "summary": "摘要还没写完
        """

        #expect(throws: SummaryParseError.unparsable) {
            try SummaryParser.parse(raw, fallbackTitle: "fallback")
        }
    }
}
