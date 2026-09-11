import Foundation
import Testing
@testable import HeyNewsKit

struct PromptBuilderTests {
    private func makeStory(
        title: String = "Show HN: My project",
        url: String? = "https://example.com/post",
        text: String? = nil,
        commentCount: Int = 12
    ) -> Story {
        Story(
            id: 1,
            title: title,
            url: url.flatMap { URL(string: $0) },
            score: 42,
            author: "nipher",
            postedAt: Date(timeIntervalSince1970: 1_160_418_111),
            commentCount: commentCount,
            type: .story,
            text: text
        )
    }

    private func makeComments(_ texts: [String]) -> StoryComments {
        let nodes = texts.enumerated().map { index, text in
            CommentNode(
                id: index + 1,
                author: "user\(index)",
                text: text,
                points: nil,
                createdAt: nil,
                children: []
            )
        }
        return StoryComments(storyID: 1, title: "t", author: "a", points: 1, topLevel: nodes)
    }

    private func commentLines(in prompt: String) -> [String] {
        prompt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("- ") }
    }

    /// 去掉 `- 作者：` 前缀，只留评论正文。字符预算按正文计算。
    private func commentText(in line: String) -> String {
        guard let separator = line.range(of: "：") else { return line }
        return String(line[separator.upperBound...])
    }

    @Test func includesStoryMetadata() {
        let pair = PromptBuilder.build(story: makeStory(), comments: nil)

        #expect(pair.user.contains("标题：Show HN: My project"))
        #expect(pair.user.contains("来源：example.com"))
        #expect(pair.user.contains("链接：https://example.com/post"))
        #expect(pair.user.contains("分数：42"))
        #expect(pair.user.contains("评论数：12"))
    }

    @Test func systemPromptAsksForJSON() {
        let pair = PromptBuilder.build(story: makeStory(), comments: nil)

        #expect(pair.system.contains("JSON"))
        #expect(pair.system.contains("title_zh"))
        #expect(pair.system.contains("comment_consensus"))
    }

    @Test func stripsHTMLFromComments() {
        let comments = makeComments(["<p>Hello &amp; <b>world</b></p>"])
        let pair = PromptBuilder.build(story: makeStory(), comments: comments)

        #expect(pair.user.contains("Hello & world"))
        #expect(pair.user.contains("<b>") == false)
        #expect(pair.user.contains("&amp;") == false)
    }

    @Test func omitsCommentBlockWhenThereAreNoComments() {
        let pair = PromptBuilder.build(story: makeStory(), comments: nil)
        #expect(pair.user.contains("评论区") == false)

        let empty = StoryComments(storyID: 1, title: nil, author: nil, points: nil, topLevel: [])
        let emptyPair = PromptBuilder.build(story: makeStory(), comments: empty)
        #expect(emptyPair.user.contains("评论区") == false)
    }

    @Test func limitsCommentCount() {
        let texts = (0..<25).map { _ in "一条普通评论" }
        let pair = PromptBuilder.build(story: makeStory(), comments: makeComments(texts))

        #expect(commentLines(in: pair.user).count == 20)
    }

    @Test func truncatesLongComment() {
        let long = String(repeating: "长", count: 700)
        let pair = PromptBuilder.build(story: makeStory(), comments: makeComments([long]))

        let lines = commentLines(in: pair.user)
        #expect(lines.count == 1)
        let line = lines.first ?? ""
        #expect(line.hasSuffix("…"))
        // 600 个字符正文 + 省略号
        #expect(commentText(in: line).count == 601)
    }

    @Test func keepsCommentExactlyAtCharacterLimit() {
        let exact = String(repeating: "限", count: 600)
        let pair = PromptBuilder.build(story: makeStory(), comments: makeComments([exact]))

        let line = commentLines(in: pair.user).first ?? ""
        #expect(line.hasSuffix("…") == false)
        #expect(commentText(in: line).count == 600)
    }

    @Test func capsTotalCommentCharacters() {
        // 每条 600 字符，预算 6000 字符 → 刚好 10 条，第 11 条超出即停止
        let long = String(repeating: "字", count: 600)
        let texts = (0..<20).map { _ in long }
        let pair = PromptBuilder.build(story: makeStory(), comments: makeComments(texts))

        let lines = commentLines(in: pair.user)
        let total = lines.map { commentText(in: $0).count }.reduce(0, +)

        #expect(lines.count == 10)
        #expect(total == 6000)
        #expect(total <= 6000)
    }

    @Test func flattensRepliesDepthFirst() {
        let child = CommentNode(
            id: 2,
            author: "child",
            text: "子评论内容",
            points: nil,
            createdAt: nil,
            children: []
        )
        let root = CommentNode(
            id: 1,
            author: "root",
            text: "顶层评论内容",
            points: nil,
            createdAt: nil,
            children: [child]
        )
        let comments = StoryComments(storyID: 1, title: nil, author: nil, points: nil, topLevel: [root])

        let pair = PromptBuilder.build(story: makeStory(), comments: comments)
        let lines = commentLines(in: pair.user)

        #expect(lines.count == 2)
        #expect(lines.first?.contains("顶层评论内容") == true)
        #expect(lines.last?.contains("子评论内容") == true)
    }

    @Test func includesSelfPostBody() {
        let story = makeStory(url: nil, text: "<p>这是自述帖正文。</p>")
        let pair = PromptBuilder.build(story: story, comments: nil)

        #expect(pair.user.contains("HN 正文"))
        #expect(pair.user.contains("这是自述帖正文。"))
        #expect(pair.user.contains("链接：无（HN 自述帖）"))
    }

    @Test func truncatesSelfPostBody() {
        let body = String(repeating: "正", count: 2000)
        let story = makeStory(url: nil, text: body)
        let pair = PromptBuilder.build(story: story, comments: nil)

        #expect(pair.user.contains(String(repeating: "正", count: 1500) + "…"))
        #expect(pair.user.contains(String(repeating: "正", count: 1501)) == false)
    }
}

struct HTMLTextTests {
    @Test func convertsParagraphsToLines() {
        let html = "第一段<p>第二段</p>第三段"
        let plain = HTMLText.plain(from: html)

        #expect(plain.contains("第一段"))
        #expect(plain.contains("第二段"))
        #expect(plain.contains("<p>") == false)
    }

    @Test func decodesNamedEntities() {
        let plain = HTMLText.plain(from: "Tom &amp; Jerry &mdash; &quot;hi&quot;")
        #expect(plain == "Tom & Jerry — \"hi\"")
    }

    @Test func decodesNumericEntities() {
        let plain = HTMLText.plain(from: "don&#x27;t panic &#8212; ok")
        #expect(plain.contains("don't panic"))
        #expect(plain.contains("— ok"))
    }

    @Test func keepsEscapedMarkupAsText() {
        let plain = HTMLText.plain(from: "用 &lt;p&gt; 表示段落")
        #expect(plain == "用 <p> 表示段落")
    }

    @Test func collapsesWhitespace() {
        let plain = HTMLText.plain(from: "  hello   world \n\n\n next  ")
        #expect(plain == "hello world\n\nnext")
    }
}

struct AIProviderConfigTests {
    @Test func buildsChatCompletionsURL() {
        let config = AIProviderConfig(
            preset: .deepseek,
            baseURL: "https://api.deepseek.com/v1/",
            summaryModel: "deepseek-v4-flash",
            analysisModel: "deepseek-v4-pro",
            isEnabled: true
        )

        #expect(config.chatCompletionsURL()?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func returnsNilForEmptyBaseURL() {
        let config = AIProviderConfig(
            preset: .custom,
            baseURL: "   ",
            summaryModel: "m",
            analysisModel: "m",
            isEnabled: true
        )

        #expect(config.chatCompletionsURL() == nil)
    }

    @Test func appliesPresetDefaults() {
        var config = AIProviderConfig.default
        config.applyPreset(.ollama)

        #expect(config.preset == .ollama)
        #expect(config.baseURL == "http://localhost:11434/v1")
        #expect(config.preset.requiresAPIKey == false)
    }

    @Test func detectsInsecurePublicTransport() {
        let publicHTTP = AIProviderConfig(
            preset: .custom,
            baseURL: "http://llm.example.com/v1",
            summaryModel: "m",
            analysisModel: "m",
            isEnabled: true
        )
        #expect(publicHTTP.isInsecureTransport)

        let localHTTP = AIProviderConfig(
            preset: .ollama,
            baseURL: "http://192.168.1.20:11434/v1",
            summaryModel: "m",
            analysisModel: "m",
            isEnabled: true
        )
        #expect(localHTTP.isInsecureTransport == false)

        let https = AIProviderConfig(
            preset: .deepseek,
            baseURL: "https://api.deepseek.com/v1",
            summaryModel: "m",
            analysisModel: "m",
            isEnabled: true
        )
        #expect(https.isInsecureTransport == false)
    }

    @Test func defaultConfigPointsAtFlashModel() {
        #expect(AIProviderConfig.default.preset == .deepseek)
        #expect(AIProviderConfig.default.summaryModel == "deepseek-v4-flash")
        #expect(AIProviderConfig.default.analysisModel == "deepseek-v4-pro")
    }
}
