import XCTest

final class Pkg6_3XCTestTests: XCTestCase {
    func testInteropNotSet() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        XCTAssertNil(interopMode)
    }
}

import Testing

struct Pkg6_3SwiftTestingTests {
    @Test func `Interop mode should not be set`() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        #expect(interopMode == nil)
    }
}
