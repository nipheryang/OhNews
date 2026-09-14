// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import OhNewsKit

@Suite("Article Insight")
struct ArticleInsightTests {
    private func makeStory(title: String = "A decade of migrations") -> Story {
        Story(
            id: "hn:1",
            sourceID: "hn",
            title: title,
            url: URL(string: "https://blog.example.com/migrations"),
            score: 412,
            author: "zdw",
            postedAt: Date(timeIntervalSince1970: 1_700_000_000),
            commentCount: 128,
            type: .story,
            text: nil
        )
    }

    // MARK: - 解析

    @Test("解析标准输出")
    func parsesStandardOutput() throws {
        let raw = """
        {"article_summary":"文章讲了迁移的十年经验。","key_points":["先做小步变更","保留回滚能力"],
         "discussion_summary":"多数人认同小步走。","discussion_trends":["对工具选型有分歧"]}
        """

        let parsed = try InsightParser.parse(raw)
        #expect(parsed.articleSummary == "文章讲了迁移的十年经验。")
        #expect(parsed.keyPoints == ["先做小步变更", "保留回滚能力"])
        #expect(parsed.discussionSummary == "多数人认同小步走。")
        #expect(parsed.discussionTrends == ["对工具选型有分歧"])
    }

    @Test("输出包在 Markdown 代码块里也能解析")
    func parsesFencedOutput() throws {
        let raw = """
        这是你要的解读：

        ```json
        {"article_summary":"总结","key_points":["一"],"discussion_summary":"","discussion_trends":[]}
        ```

        希望有帮助。
        """

        let parsed = try InsightParser.parse(raw)
        #expect(parsed.articleSummary == "总结")
        // 空字符串要归一成 nil，界面靠它决定要不要显示讨论区一节。
        #expect(parsed.discussionSummary == nil)
        #expect(parsed.discussionTrends.isEmpty)
    }

    @Test("接受驼峰与中文的字段名变体")
    func acceptsFieldAliases() throws {
        let raw = """
        {"articleSummary":"总结","keyPoints":["一","二"],"discussionSummary":"观点","discussionTrends":["趋势"]}
        """
        let parsed = try InsightParser.parse(raw)
        #expect(parsed.articleSummary == "总结")
        #expect(parsed.keyPoints.count == 2)
        #expect(parsed.discussionSummary == "观点")
    }

    @Test("只有要点、没有总述也算可用")
    func acceptsPointsOnly() throws {
        let raw = #"{"key_points":["只有要点"]}"#
        let parsed = try InsightParser.parse(raw)
        #expect(parsed.articleSummary.isEmpty)
        #expect(parsed.keyPoints == ["只有要点"])
    }

    @Test("要点为空时也接受只有总述")
    func acceptsSummaryOnly() throws {
        let raw = #"{"article_summary":"只有总述","key_points":[]}"#
        let parsed = try InsightParser.parse(raw)
        #expect(parsed.articleSummary == "只有总述")
        #expect(parsed.keyPoints.isEmpty)
    }

    @Test("两者皆空视为解析失败")
    func rejectsEmptyResult() {
        #expect(throws: InsightParseError.unparsable) {
            try InsightParser.parse(#"{"article_summary":"","key_points":[]}"#)
        }
    }

    @Test("完全不是 JSON 时抛错")
    func rejectsGarbage() {
        #expect(throws: InsightParseError.unparsable) {
            try InsightParser.parse("模型今天不想干活")
        }
    }

    @Test("要点是整段文字时按行拆开")
    func splitsStringPoints() throws {
        let raw = #"{"article_summary":"总述","key_points":"1. 第一条\n2. 第二条\n- 第三条"}"#
        let parsed = try InsightParser.parse(raw)
        #expect(parsed.keyPoints == ["第一条", "第二条", "第三条"])
    }

    @Test("剥掉行首的列表标记")
    func stripsListMarkers() {
        #expect(InsightParser.stringList(from: ["- 甲", "• 乙", "1. 丙", "2、丁"]) == ["甲", "乙", "丙", "丁"])
        // 正常句子里的连字符不该被动。
        #expect(InsightParser.stringList(from: ["state-of-the-art 模型"]) == ["state-of-the-art 模型"])
    }

    @Test("要点去重且限量")
    func dedupesAndLimitsPoints() {
        let many = (0..<20).map { "要点\($0)" } + ["要点0"]
        let result = InsightParser.stringList(from: many)
        #expect(result.count == 8)
        #expect(Set(result).count == result.count)
    }

    // MARK: - Prompt

    @Test("prompt 里包含正文与标题")
    func promptCarriesArticle() {
        let story = makeStory(title: "A decade of migrations")
        let pair = InsightPromptBuilder.build(
            story: story,
            articleHTML: "<p>正文第一段。</p><p>正文第二段。</p>",
            discussionHTML: nil
        )

        #expect(pair.user.contains("A decade of migrations"))
        #expect(pair.user.contains("正文第一段"))
        #expect(pair.user.contains("正文第二段"))
        // system 段要要求这四个字段。
        #expect(pair.system.contains("article_summary"))
        #expect(pair.system.contains("discussion_trends"))
    }

    @Test("提示词把长度上限写死，避免模型长篇大论")
    func promptCapsTheLength() {
        // 面板是上限固定的盒子，内容越短越好。上限写在提示词里，
        // 这条断言把它钉住——以后想放宽得先改这里的数字。
        let system = InsightPromptBuilder.systemPrompt()
        #expect(system.contains("不超过 50 字"))
        #expect(system.contains("最多 3 条"))
        #expect(system.contains("不超过 18 字"))
        #expect(system.contains("最多 2 条"))
    }

    @Test("没取到正文时明确告知模型，而不是留空")
    func tellsModelWhenArticleMissing() {
        let pair = InsightPromptBuilder.build(
            story: makeStory(),
            articleHTML: nil,
            discussionHTML: nil
        )
        #expect(pair.user.contains("（未能取到正文）"))
    }

    @Test("超长正文会截断")
    func truncatesLongArticle() {
        let long = String(repeating: "字", count: InsightPromptBuilder.maxArticleCharacters + 500)
        let pair = InsightPromptBuilder.build(
            story: makeStory(),
            articleHTML: "<p>\(long)</p>",
            discussionHTML: nil
        )
        #expect(pair.user.count < long.count)
        #expect(pair.user.contains("……"))
    }

    @Test("讨论区剥成纯文本后送入")
    func stripsDiscussionMarkup() {
        let html = "<div class=\"comment\"><p>第一条观点</p></div>"
        let excerpt = InsightPromptBuilder.commentExcerpt(from: html, limits: .default)
        #expect(excerpt.contains("第一条观点"))
        #expect(excerpt.contains("<p>") == false)
        #expect(excerpt.contains("comment") == false)
    }

    @Test("没有讨论区时 prompt 里不出现评论区一节")
    func omitsDiscussionSectionWhenEmpty() {
        let pair = InsightPromptBuilder.build(
            story: makeStory(),
            articleHTML: "<p>正文</p>",
            discussionHTML: nil
        )
        #expect(pair.user.contains("评论区") == false)

        let pair2 = InsightPromptBuilder.build(
            story: makeStory(),
            articleHTML: "<p>正文</p>",
            discussionHTML: "<p>观点</p>"
        )
        #expect(pair2.user.contains("评论区"))
    }

    // MARK: - 模型

    private func insight(contentHash: String = "abc", model: String = "m") -> ArticleInsight {
        ArticleInsight(
            itemID: "hn:1",
            contentHash: contentHash,
            articleSummary: "总结",
            keyPoints: ["一"],
            discussionSummary: "观点",
            discussionTrends: ["趋势"],
            modelName: model,
            promptVersion: InsightPromptVersion.current,
            generatedAt: Date()
        )
    }

    @Test("内容或配置变了就不再匹配")
    func matchesOnlyWhenEverythingLinesUp() {
        let value = insight()
        #expect(value.matches(
            contentHash: "abc",
            modelName: "m",
            promptVersion: InsightPromptVersion.current
        ))
        #expect(value.matches(
            contentHash: "changed",
            modelName: "m",
            promptVersion: InsightPromptVersion.current
        ) == false)
        #expect(value.matches(
            contentHash: "abc",
            modelName: "other",
            promptVersion: InsightPromptVersion.current
        ) == false)
        #expect(value.matches(
            contentHash: "abc",
            modelName: "m",
            promptVersion: "i0"
        ) == false)
    }

    @Test("没有可展示内容时 hasContent 为假")
    func hasContentDetectsEmpty() {
        #expect(insight().hasContent)

        let empty = ArticleInsight(
            itemID: "hn:1",
            contentHash: "abc",
            articleSummary: "",
            keyPoints: [],
            discussionSummary: nil,
            discussionTrends: [],
            modelName: "m",
            promptVersion: InsightPromptVersion.current,
            generatedAt: Date()
        )
        #expect(empty.hasContent == false)
    }

    @Test("解读的版本号与摘要的分开")
    func versionIsIndependent() {
        #expect(InsightPromptVersion.current != PromptVersion.current)
    }
}
