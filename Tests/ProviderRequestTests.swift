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

    func testOpenAIURLRequestHasBearerAuthAndURL() throws {
        let profile = ProviderProfile(
            id: "x", name: "n", kind: .openAICompatible,
            baseURL: "https://api.example.com/", chatEndpoint: "/v1/chat/completions", model: "m"
        )
        let urlReq = try ProviderRequestFactory.urlRequest(
            profile: profile, apiKey: "KEY",
            request: LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u")
        )
        XCTAssertEqual(urlReq.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(urlReq.httpMethod, "POST")
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "Authorization"), "Bearer KEY")
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testAnthropicURLRequestHasAPIKeyHeaders() throws {
        let profile = ProviderProfile(
            id: "x", name: "n", kind: .anthropicMessages,
            baseURL: "https://api.anthropic.com", chatEndpoint: "/v1/messages", model: "m"
        )
        let urlReq = try ProviderRequestFactory.urlRequest(
            profile: profile, apiKey: "KEY",
            request: LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u")
        )
        XCTAssertEqual(urlReq.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "x-api-key"), "KEY")
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(urlReq.value(forHTTPHeaderField: "Authorization"))
    }

    func testExtraHeadersApplied() throws {
        let profile = ProviderProfile(
            id: "x", name: "n", kind: .openAICompatible,
            baseURL: "https://h.example.com", chatEndpoint: "/v1/chat/completions", model: "m",
            extraHeadersJSON: #"{"X-Test":"yes"}"#
        )
        let urlReq = try ProviderRequestFactory.urlRequest(
            profile: profile, apiKey: "K",
            request: LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u")
        )
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "X-Test"), "yes")
    }

    func testInvalidURLThrows() {
        let profile = ProviderProfile(
            id: "x", name: "n", kind: .openAICompatible,
            baseURL: "", chatEndpoint: "", model: "m"
        )
        XCTAssertThrowsError(try ProviderRequestFactory.urlRequest(
            profile: profile, apiKey: "K",
            request: LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u")
        )) { XCTAssertEqual($0 as? LLMProviderError, .invalidURL) }
    }
}
