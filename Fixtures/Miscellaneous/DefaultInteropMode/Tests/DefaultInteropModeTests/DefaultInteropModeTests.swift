import XCTest

final class DefaultInteropModeXCTestTests: XCTestCase {
    func testInteropSetToComplete() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        XCTAssertEqual(interopMode, "complete")
    }
}

import Testing

struct DefaultInteropModeSwiftTestingTests {
    @Test func `Interop mode should be set to complete`() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        #expect(interopMode == "complete")
    }
}
