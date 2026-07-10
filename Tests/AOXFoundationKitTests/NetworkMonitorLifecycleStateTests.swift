import XCTest
@testable import AOXFoundationKit

final class NetworkMonitorLifecycleStateTests: XCTestCase {
    func testDuplicateStartDoesNotReplaceActiveGeneration() throws {
        var state = NetworkMonitorLifecycleState()

        let firstGeneration = try XCTUnwrap(state.beginMonitoring())

        XCTAssertTrue(state.acceptsCallback(generation: firstGeneration))
        XCTAssertNil(state.beginMonitoring())
        XCTAssertEqual(state.generation, firstGeneration)
        XCTAssertTrue(state.acceptsCallback(generation: firstGeneration))
    }

    func testStopImmediatelyRejectsCallbacksFromPreviousMonitor() throws {
        var state = NetworkMonitorLifecycleState()
        let stoppedGeneration = try XCTUnwrap(state.beginMonitoring())

        XCTAssertNotNil(state.endMonitoring())

        XCTAssertFalse(state.isMonitoring)
        XCTAssertFalse(state.acceptsCallback(generation: stoppedGeneration))
        XCTAssertNil(state.endMonitoring())
    }

    func testRestartAcceptsOnlyNewestMonitorGeneration() throws {
        var state = NetworkMonitorLifecycleState()
        let oldGeneration = try XCTUnwrap(state.beginMonitoring())
        XCTAssertNotNil(state.endMonitoring())

        let newGeneration = try XCTUnwrap(state.beginMonitoring())

        XCTAssertNotEqual(oldGeneration, newGeneration)
        XCTAssertFalse(state.acceptsCallback(generation: oldGeneration))
        XCTAssertTrue(state.acceptsCallback(generation: newGeneration))
    }
}
