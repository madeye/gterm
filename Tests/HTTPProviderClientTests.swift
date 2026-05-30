import XCTest

/// URLProtocol stub so the client can be exercised end-to-end without a network.
final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class HTTPProviderClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testCompleteSuccess() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer K")
            let body = #"{"choices":[{"message":{"content":"git status"}}],"usage":{"total_tokens":3}}"#
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        let client = HTTPProviderClient(profile: .openAIPreset(), apiKey: "K", session: MockURLProtocol.session())
        let r = try await client.complete(LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u"))
        XCTAssertEqual(r.text, "git status")
        XCTAssertEqual(r.totalTokens, 3)
    }

    func testMissingAPIKeyThrows() async {
        let client = HTTPProviderClient(profile: .openAIPreset(), apiKey: "   ", session: MockURLProtocol.session())
        do {
            _ = try await client.complete(LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .missingAPIKey)
        }
    }

    func testHTTPErrorMapsToInvalidStatus() async {
        MockURLProtocol.handler = { request in
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"error":"unauthorized"}"#.utf8))
        }
        let client = HTTPProviderClient(profile: .openAIPreset(), apiKey: "K", session: MockURLProtocol.session())
        do {
            _ = try await client.complete(LLMRequest(model: "m", systemPrompt: "s", userPrompt: "u"))
            XCTFail("expected throw")
        } catch {
            guard case LLMProviderError.invalidStatus(let code, _) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertEqual(code, 401)
        }
    }
}
