// Copyright (C) 2026 Nipher
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import OhNewsKit

struct HNJSONParserTests {
    @Test func parsesStoryIDList() throws {
        let ids = try HNJSONParser.parseStoryIDs(from: try Fixture.data("topstories"))
        #expect(ids.count == 20)
        #expect(ids.allSatisfy { $0 > 0 })
    }

    @Test func throwsOnMalformedIDList() {
        #expect(throws: HNParseError.malformedJSON) {
            try HNJSONParser.parseStoryIDs(from: Data("not json".utf8))
        }
    }

    @Test func parsesStoryWithExternalURL() throws {
        let story = try #require(try HNJSONParser.parseStory(from: try Fixture.data("item-story")))

        #expect(story.id == "hn:1")
        #expect(story.sourceID == "hn")
        #expect(story.title == "Y Combinator")
        #expect(story.author == "pg")
        #expect(story.url?.absoluteString == "http://ycombinator.com")
        #expect(story.commentCount == 3)
        #expect(story.type == .story)
        #expect(story.sourceHost == "ycombinator.com")
        #expect(story.isSelfPost == false)
    }

    @Test func parsesAskHNWithoutURL() throws {
        let story = try #require(try HNJSONParser.parseStory(from: try Fixture.data("item-ask")))

        #expect(story.url == nil)
        #expect(story.sourceHost == nil)
        #expect(story.text?.isEmpty == false)
        #expect(story.isSelfPost)
        #expect(story.title.hasPrefix("Ask HN"))
    }

    @Test func parsesJobItem() throws {
        let story = try #require(try HNJSONParser.parseStory(from: try Fixture.data("item-job")))

        #expect(story.type == .job)
        #expect(story.url != nil)
        #expect(story.title.isEmpty == false)
    }

    @Test func returnsNilForDeletedItem() throws {
        let story = try HNJSONParser.parseStory(from: try Fixture.data("item-deleted"))
        #expect(story == nil)
    }

    @Test func throwsOnMalformedItem() {
        #expect(throws: HNParseError.malformedJSON) {
            try HNJSONParser.parseStory(from: Data("[]".utf8))
        }
    }

    @Test func parsesCommentTree() throws {
        let comments = try #require(
            try HNJSONParser.parseStoryComments(from: try Fixture.data("algolia-comments"))
        )

        #expect(comments.storyID == "hn:1")
        #expect(comments.title == "Y Combinator")
        // 样本结构：顶层 1 条，其下还有两层，共 3 个评论节点。
        #expect(comments.topLevel.count == 1)
        #expect(comments.totalCount == 3)

        let nested = try #require(comments.topLevel.first?.children.first)
        #expect(nested.id == 17)
        #expect(nested.text == "Is there anywhere to eat on Sandhill Road?")
        #expect(nested.createdAt != nil)
        #expect(nested.flattened.count == 1)
    }

    @Test func returnsNilWhenCommentPayloadHasNoID() throws {
        let comments = try HNJSONParser.parseStoryComments(from: Data("{}".utf8))
        #expect(comments == nil)
    }
}
