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

/// Reasoning models (o-series, gpt-5+, e.g. gpt-6-luna) reject `temperature`
/// with HTTP 400 and take `reasoning_effort` instead.
final class OpenAIModelTraitsTests: XCTestCase {
    func testDetectsReasoningModels() {
        for model in ["gpt-6-luna", "gpt-6-sol", "gpt-6.1-sol", "gpt-5", "gpt-5-mini", "gpt-5.2",
                      "o1", "o3-mini", "o4-mini", "openai/gpt-6-luna", "GPT-6-Luna"] {
            XCTAssertTrue(OpenAIModelTraits.isReasoningModel(model), model)
        }
        for model in ["gpt-4o-mini", "gpt-4.1", "gpt-5-chat-latest", "deepseek-v4-flash",
                      "glm-5.1", "kimi-k2.6", "llama-3.1-8b-instant", "openai/gpt-4o-mini", "omni"] {
            XCTAssertFalse(OpenAIModelTraits.isReasoningModel(model), model)
        }
    }

    func testPicksLowestLatencyReasoningEffort() {
        XCTAssertEqual(OpenAIModelTraits.reasoningEffort(for: "gpt-6-luna"), "none")
        XCTAssertEqual(OpenAIModelTraits.reasoningEffort(for: "openai/gpt-6-luna"), "none")
        XCTAssertEqual(OpenAIModelTraits.reasoningEffort(for: "gpt-5.1"), "none")
        XCTAssertEqual(OpenAIModelTraits.reasoningEffort(for: "gpt-5-mini"), "minimal")
        XCTAssertEqual(OpenAIModelTraits.reasoningEffort(for: "o4-mini"), "low")
        XCTAssertNil(OpenAIModelTraits.reasoningEffort(for: "gpt-4o-mini"))
    }

    func testReasoningModelBodyOmitsTemperature() {
        let profile = ProviderProfile.openAIPreset()
        let req = LLMRequest(model: "gpt-6-luna", systemPrompt: "sys", userPrompt: "usr", temperature: 0, maxTokens: 32)
        let body = ProviderRequestFactory.body(profile: profile, request: req)

        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 32)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
    }

    func testClassicModelBodyKeepsTemperature() {
        let profile = ProviderProfile.openAIPreset()
        let req = LLMRequest(model: "gpt-4o-mini", systemPrompt: "sys", userPrompt: "usr", temperature: 0.1)
        let body = ProviderRequestFactory.body(profile: profile, request: req)

        XCTAssertEqual(body["temperature"] as? Double, 0.1)
        XCTAssertNil(body["reasoning_effort"])
    }
}
