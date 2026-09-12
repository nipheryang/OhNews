// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

@Suite("TranslationPromptBuilder")
struct TranslationPromptBuilderTests {
    private func segment(_ index: Int, _ text: String) -> ArticleSegmenter.Segment {
        ArticleSegmenter.Segment(index: index, text: text, links: [])
    }

    @Test func systemPromptStatesTheHardRequirements() {
        let prompt = TranslationPromptBuilder.systemPrompt

        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("translations"))
        // 占位符必须原样保留，否则链接会丢。
        #expect(prompt.contains("[[0]]"))
        // 数量与顺序是这一版最怕出错的地方。
        #expect(prompt.contains("条数与顺序"))
    }

    @Test func buildsJSONPayload() throws {
        let request = TranslationPromptBuilder.build(segments: [
            segment(0, "First paragraph."),
            segment(1, "Second paragraph.")
        ])

        #expect(request.system == TranslationPromptBuilder.systemPrompt)

        let data = try #require(request.user.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let segments = try #require(object["segments"] as? [String])
        #expect(segments == ["First paragraph.", "Second paragraph."])
    }

    @Test func keepsPlaceholdersInPayload() throws {
        let request = TranslationPromptBuilder.build(segments: [
            segment(0, "See [[0]] for details.")
        ])

        #expect(request.user.contains("[[0]]"))
    }

    @Test func handlesEmptySegments() throws {
        let request = TranslationPromptBuilder.build(segments: [])

        let data = try #require(request.user.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["segments"] as? [String])?.isEmpty == true)
    }
}

@Suite("TranslationParser")
struct TranslationParserTests {
    @Test func parsesCleanJSON() throws {
        let raw = #"{"translations": ["第一段", "第二段"]}"#

        let result = try TranslationParser.parse(raw, expectedCount: 2)

        #expect(result == ["第一段", "第二段"])
    }

    @Test func parsesFencedJSON() throws {
        let raw = """
        ```json
        {"translations": ["只有一段"]}
        ```
        """

        #expect(try TranslationParser.parse(raw, expectedCount: 1) == ["只有一段"])
    }

    @Test func skipsSurroundingProse() throws {
        let raw = "好的，以下是译文：{\"translations\": [\"译文\"]} 希望有帮助。"

        #expect(try TranslationParser.parse(raw, expectedCount: 1) == ["译文"])
    }

    /// 数量不符必须报错，不能猜对应关系。
    @Test func rejectsCountMismatch() {
        let raw = #"{"translations": ["只有一条"]}"#

        #expect(throws: TranslationParseError.countMismatch(expected: 3, got: 1)) {
            try TranslationParser.parse(raw, expectedCount: 3)
        }
    }

    @Test func rejectsUnparsableOutput() {
        #expect(throws: TranslationParseError.unparsable) {
            try TranslationParser.parse("我无法完成翻译。", expectedCount: 1)
        }
    }

    @Test func toleratesNonStringEntries() throws {
        let raw = #"{"translations": ["第一段", 42]}"#

        // 非字符串项退化为空串，但数量仍然吻合，不整批作废。
        #expect(try TranslationParser.parse(raw, expectedCount: 2) == ["第一段", ""])
    }

    @Test func acceptsAlternativeFieldNames() throws {
        let raw = #"{"result": ["甲", "乙"]}"#

        #expect(try TranslationParser.parse(raw, expectedCount: 2) == ["甲", "乙"])
    }

    @Test func splitsStringPayloadByLines() throws {
        let raw = #"{"translations": "第一段\n第二段"}"#

        #expect(try TranslationParser.parse(raw, expectedCount: 2) == ["第一段", "第二段"])
    }

    @Test func rejectsEmptyArrayAgainstExpectedCount() {
        #expect(throws: TranslationParseError.countMismatch(expected: 1, got: 0)) {
            try TranslationParser.parse(#"{"translations": []}"#, expectedCount: 1)
        }
    }
}
