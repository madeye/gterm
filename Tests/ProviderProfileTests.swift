import XCTest

final class ProviderProfileTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let profile = ProviderProfile.deepSeekPreset()
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ProviderProfile.self, from: data)
        XCTAssertEqual(profile, decoded)
    }

    func testPresetsCoverBothAPIShapes() {
        let presets = ProviderProfile.presets()
        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.contains { $0.kind == .openAICompatible })
        XCTAssertTrue(presets.contains { $0.kind == .anthropicMessages })
    }

    func testPresetsHaveUniqueIDs() {
        let ids = ProviderProfile.presets().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testChinaProvidersPresent() {
        let presets = ProviderProfile.presets()
        func preset(_ id: String) -> ProviderProfile? { presets.first { $0.id == id } }

        // Models the user asked for.
        XCTAssertEqual(preset("preset.deepseek")?.model, "deepseek-v4-flash")
        XCTAssertEqual(preset("preset.kimi")?.model, "kimi-k2.6")
        XCTAssertEqual(preset("preset.glm")?.model, "glm-5.1")
        XCTAssertNotNil(preset("preset.minimax"))

        // All China providers speak the OpenAI-compatible API (SSE streaming).
        for id in ["preset.deepseek", "preset.kimi", "preset.minimax", "preset.glm"] {
            XCTAssertEqual(preset(id)?.kind, .openAICompatible, "\(id) should be openAICompatible")
        }
    }

    func testChinaProviderEndpoints() {
        let presets = ProviderProfile.presets()
        func preset(_ id: String) -> ProviderProfile? { presets.first { $0.id == id } }

        XCTAssertEqual(preset("preset.deepseek")?.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(preset("preset.kimi")?.baseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(preset("preset.minimax")?.baseURL, "https://api.minimaxi.com/v1")
        XCTAssertEqual(preset("preset.glm")?.baseURL, "https://open.bigmodel.cn/api/paas/v4")
        for id in ["preset.deepseek", "preset.kimi", "preset.minimax", "preset.glm"] {
            XCTAssertEqual(preset(id)?.chatEndpoint, "/chat/completions")
        }
    }
}
