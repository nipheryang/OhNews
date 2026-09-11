import Foundation
import Testing
@testable import OhNewsKit

struct ExtractionFallbackTests {
    @Test func usesArticleWhenHTMLPresent() {
        let outcome = ExtractionOutcome(
            articleHTML: "<p>正文</p>",
            commentCount: 12,
            externalURL: URL(string: "https://example.com/post")
        )
        #expect(ExtractionFallback.decide(outcome) == .article)
    }

    @Test func treatsEmptyHTMLAsMissing() {
        let outcome = ExtractionOutcome(
            articleHTML: "",
            commentCount: 12,
            externalURL: URL(string: "https://example.com/post")
        )
        #expect(ExtractionFallback.decide(outcome) == .titleAndComments)
    }

    @Test func fallsBackToCommentsWhenExtractionFailed() {
        let outcome = ExtractionOutcome(
            articleHTML: nil,
            commentCount: 4,
            externalURL: URL(string: "https://nytimes.com/paywalled")
        )
        #expect(ExtractionFallback.decide(outcome) == .titleAndComments)
    }

    @Test func fallsBackToTitleOnlyWhenNothingElse() {
        let outcome = ExtractionOutcome(
            articleHTML: nil,
            commentCount: 0,
            externalURL: URL(string: "https://example.com/post.pdf")
        )
        #expect(ExtractionFallback.decide(outcome) == .titleOnly)
    }
}

struct RetryPolicyTests {
    @Test func retriesRateLimitAndServerErrors() {
        #expect(RetryPolicy.isRetryable(statusCode: 429))
        #expect(RetryPolicy.isRetryable(statusCode: 500))
        #expect(RetryPolicy.isRetryable(statusCode: 503))
    }

    @Test func doesNotRetryClientErrors() {
        #expect(RetryPolicy.isRetryable(statusCode: 400) == false)
        #expect(RetryPolicy.isRetryable(statusCode: 404) == false)
        #expect(RetryPolicy.isRetryable(statusCode: 200) == false)
    }

    @Test func backsOffThenGivesUp() {
        let policy = RetryPolicy.default
        #expect(policy.delay(afterAttempt: 1) == .seconds(1))
        #expect(policy.delay(afterAttempt: 2) == .seconds(3))
        #expect(policy.delay(afterAttempt: 3) == nil)
    }

    @Test func clampsToLastDelayWhenAttemptsExceedProvidedDelays() {
        let policy = RetryPolicy(attempts: 5, delays: [.seconds(2)])
        #expect(policy.delay(afterAttempt: 4) == .seconds(2))
        #expect(policy.delay(afterAttempt: 5) == nil)
    }
}
