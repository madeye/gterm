import XCTest

final class ProviderProfileTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let profile = ProviderProfile.openAIPreset()
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
}
