import XCTest
@testable import SushiTray

final class ModelStateTests: XCTestCase {
    func testRequestedModelDeterminesStatusWhenAnotherModelIsReady() {
        let ready = SushiModel(id: "other", loaded: true, state: "ready")
        let loading = SushiModel(id: "selected", state: "loading")
        XCTAssertEqual(ModelsClient.loadState(models: [ready, loading], preferredID: "selected"), .loading)
        let failed = SushiModel(id: "selected", state: "error")
        XCTAssertEqual(ModelsClient.loadState(models: [ready, failed], preferredID: "selected"), .error)
        XCTAssertEqual(ModelsClient.loadState(models: [ready, failed], preferredID: "other"), .ready)
    }

    func testModelStatusTransitionsFromLoadingToReadyAndUnloaded() {
        XCTAssertEqual(ModelsClient.loadState(models: [SushiModel(id: "pack", state: "loading")], preferredID: "pack"), .loading)
        XCTAssertEqual(ModelsClient.loadState(models: [SushiModel(id: "pack", state: "ready")], preferredID: "pack"), .ready)
        XCTAssertEqual(ModelsClient.loadState(models: [SushiModel(id: "pack", state: "unloaded")], preferredID: "pack"), .unloaded)
        XCTAssertEqual(ModelsClient.loadState(models: [], preferredID: nil), .unloaded)
    }

    func testNoSelectedModelUsesLiveLoadingThenReadyThenError() {
        let ready = SushiModel(id: "ready", state: "ready")
        let loading = SushiModel(id: "loading", state: "loading")
        let failed = SushiModel(id: "failed", state: "error")
        XCTAssertEqual(ModelsClient.loadState(models: [ready, loading, failed], preferredID: nil), .loading)
        XCTAssertEqual(ModelsClient.loadState(models: [ready, failed], preferredID: nil), .ready)
        XCTAssertEqual(ModelsClient.loadState(models: [failed], preferredID: nil), .error)
    }
}
