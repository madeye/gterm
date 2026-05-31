import XCTest

final class ProviderResponseTests: XCTestCase {
    func testOpenAIParsing() throws {
        let data = Data(#"{"id":"abc","model":"m","choices":[{"message":{"content":"git status"}}],"usage":{"total_tokens":7,"prompt_tokens":5,"completion_tokens":2}}"#.utf8)
        let r = try ProviderResponseParser.parse(data: data, kind: .openAICompatible)
        XCTAssertEqual(r.text, "git status")
        XCTAssertEqual(r.model, "m")
        XCTAssertEqual(r.totalTokens, 7)
        XCTAssertEqual(r.promptTokens, 5)
        XCTAssertEqual(r.completionTokens, 2)
    }

    func testOpenAIReasoningFallback() throws {
        // Content empty but reasoning_content present: surface the reasoning.
        let data = Data(#"{"choices":[{"message":{"content":"","reasoning_content":"ls -la"}}]}"#.utf8)
        let r = try ProviderResponseParser.parse(data: data, kind: .openAICompatible)
        XCTAssertEqual(r.text, "ls -la")
    }

    func testAnthropicParsing() throws {
        let data = Data(#"{"id":"m1","model":"claude","content":[{"type":"text","text":"ls -la"}],"usage":{"input_tokens":4,"output_tokens":3}}"#.utf8)
        let r = try ProviderResponseParser.parse(data: data, kind: .anthropicMessages)
        XCTAssertEqual(r.text, "ls -la")
        XCTAssertEqual(r.promptTokens, 4)
        XCTAssertEqual(r.completionTokens, 3)
        XCTAssertEqual(r.totalTokens, 7)
    }

    func testAnthropicSkipsThinkingBlocks() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"final"}]}"#.utf8)
        let r = try ProviderResponseParser.parse(data: data, kind: .anthropicMessages)
        XCTAssertEqual(r.text, "final")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try ProviderResponseParser.parse(data: Data("nope".utf8), kind: .openAICompatible)) {
            XCTAssertEqual($0 as? LLMProviderError, .malformedJSON)
        }
    }

    func testEmptyOutputThrows() {
        XCTAssertThrowsError(try ProviderResponseParser.parse(data: Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8), kind: .openAICompatible)) {
            XCTAssertEqual($0 as? LLMProviderError, .emptyOutput)
        }
    }
}
