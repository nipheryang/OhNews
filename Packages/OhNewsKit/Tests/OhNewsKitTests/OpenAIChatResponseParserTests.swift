import Foundation
import Testing
@testable import OhNewsKit

struct OpenAIChatResponseParserTests {
    @Test func readsMessageContent() throws {
        let payload = """
        {"choices":[{"message":{"role":"assistant","content":"{\\"summary\\":\\"摘要\\"}"}}]}
        """

        let content = try OpenAIChatResponseParser.content(from: Data(payload.utf8))
        #expect(content == "{\"summary\":\"摘要\"}")
    }

    @Test func fallsBackToReasoningContent() throws {
        let payload = """
        {"choices":[{"message":{"role":"assistant","content":"","reasoning_content":"思考后的结果"}}]}
        """

        let content = try OpenAIChatResponseParser.content(from: Data(payload.utf8))
        #expect(content == "思考后的结果")
    }

    @Test func throwsWhenChoicesMissing() {
        #expect(throws: OpenAIChatParseError.unexpectedPayload) {
            try OpenAIChatResponseParser.content(from: Data("{\"error\":\"bad key\"}".utf8))
        }
    }

    @Test func throwsWhenChoicesEmpty() {
        #expect(throws: OpenAIChatParseError.unexpectedPayload) {
            try OpenAIChatResponseParser.content(from: Data("{\"choices\":[]}".utf8))
        }
    }

    @Test func throwsWhenContentBlank() {
        let payload = """
        {"choices":[{"message":{"content":"   "}}]}
        """

        #expect(throws: OpenAIChatParseError.unexpectedPayload) {
            try OpenAIChatResponseParser.content(from: Data(payload.utf8))
        }
    }

    @Test func throwsOnNonJSONBody() {
        #expect(throws: OpenAIChatParseError.unexpectedPayload) {
            try OpenAIChatResponseParser.content(from: Data("<html>502 Bad Gateway</html>".utf8))
        }
    }
}
