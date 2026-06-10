import XCTest

final class RespectUserInteropModeXCTestTests: XCTestCase {
    /// This test should be called with `SWIFT_TESTING_XCTEST_INTEROP_MODE` already set to none prior to invoking Swift Package.
    func testInteropSetToNone() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        XCTAssertEqual(interopMode, "none")
    }
}

import Testing

struct RespectUserInteropModeSwiftTestingTests {
    /// This test should be called with `SWIFT_TESTING_XCTEST_INTEROP_MODE` already set to none prior to invoking Swift Package.
    @Test func `Interop mode should be set to none`() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        #expect(interopMode == "none")
    }
}
