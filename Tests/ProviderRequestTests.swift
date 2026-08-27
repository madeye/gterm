import XCTest

final class ProviderRequestTests: XCTestCase {
    func testOpenAIBodyEncoding() {
        let profile = ProviderProfile.openAIPreset()
        let req = LLMRequest(model: "gpt-4o-mini", systemPrompt: "sys", userPrompt: "usr", maxTokens: 32)
        let body = ProviderRequestFactory.body(profile: profile, request: req)

        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(body["max_tokens"] as? Int, 32)
        XCTAssertNil(body["system"])
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.first?["content"], "sys")
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "usr")
    }

    func testAnthropicBodyEncoding() {
        let profile = ProviderProfile.anthropicPreset()
        let req = LLMRequest(model: "claude-x", systemPrompt: "sys", userPrompt: "usr", maxTokens: 64)
        let body = ProviderRequestFactory.body(profile: profile, request: req)

        XCTAssertEqual(body["model"] as? String, "claude-x")
        XCTAssertEqual(body["system"] as? String, "sys")
        XCTAssertEqual(body["max_tokens"] as? Int, 64)
        let messages = body["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "usr")
    }
}

/// Covers the streaming URL construction the OpenAI SDK consumes (the runse
/// `ProviderURLSplitter`).
final class ProviderURLSplitterTests: XCTestCase {
    func testSplitsStandardOpenAIBase() throws {
        let (scheme, host, port, basePath) = try ProviderURLSplitter.split(
            baseURL: "https://api.openai.com", endpoint: "/v1/chat/completions"
        )
        XCTAssertEqual(scheme, "https")
        XCTAssertEqual(host, "api.openai.com")
        XCTAssertEqual(port, 443)
        // "/chat/completions" is stripped (the SDK re-appends it); "/v1" remains.
        XCTAssertEqual(basePath, "/v1")
    }

    func testSplitsChinaProviderWithPathPrefix() throws {
        // GLM keeps its "/api/paas/v4" prefix once "/chat/completions" is stripped.
        let (_, host, _, basePath) = try ProviderURLSplitter.split(
            baseURL: "https://open.bigmodel.cn/api/paas/v4", endpoint: "/chat/completions"
        )
        XCTAssertEqual(host, "open.bigmodel.cn")
        XCTAssertEqual(basePath, "/api/paas/v4")
    }

    func testSplitsDeepSeekBareBase() throws {
        let (_, host, _, basePath) = try ProviderURLSplitter.split(
            baseURL: "https://api.deepseek.com", endpoint: "/chat/completions"
        )
        XCTAssertEqual(host, "api.deepseek.com")
        XCTAssertEqual(basePath, "")
    }

    func testHostWithoutSchemeDefaultsToHTTPS() throws {
        let (scheme, host, port, _) = try ProviderURLSplitter.split(
            baseURL: "api.example.com", endpoint: "/v1/chat/completions"
        )
        XCTAssertEqual(scheme, "https")
        XCTAssertEqual(host, "api.example.com")
        XCTAssertEqual(port, 443)
    }

    func testInvalidURLDoesNotFallBackToOpenAI() {
        let bad = ["", "https://", "   ", "not a url", "ftp://api.example.com"]
        for base in bad {
            XCTAssertThrowsError(
                try ProviderURLSplitter.split(baseURL: base, endpoint: "/v1/chat/completions"),
                "expected invalidURL for \(base)"
            ) { error in
                XCTAssertEqual(error as? LLMProviderError, .invalidURL)
            }
        }
    }

    func testExtraHeadersParsing() {
        XCTAssertEqual(ProviderURLSplitter.extraHeaders(#"{"X-Test":"yes"}"#), ["X-Test": "yes"])
        XCTAssertEqual(ProviderURLSplitter.extraHeaders("not json"), [:])
    }
}
