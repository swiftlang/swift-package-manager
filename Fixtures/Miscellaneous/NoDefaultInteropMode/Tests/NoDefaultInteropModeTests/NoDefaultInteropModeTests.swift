import XCTest

final class NoDefaultInteropModeXCTestTests: XCTestCase {
    func testInteropNotSet() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        XCTAssertNil(interopMode)
    }
}

import Testing

struct NoDefaultInteropModeSwiftTestingTests {
    @Test func `Interop mode should not be set`() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        #expect(interopMode == nil)
    }
}
