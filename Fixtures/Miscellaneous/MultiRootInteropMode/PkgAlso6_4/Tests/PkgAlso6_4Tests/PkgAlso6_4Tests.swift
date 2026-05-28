import XCTest

final class PkgAlso6_4XCTestTests: XCTestCase {
    func testInteropNotSet() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        // Normally the default should be set here, but this is run in a workspace with tools-version < 6.4
        XCTAssertNil(interopMode)
    }
}

import Testing

struct PkgAlso6_4SwiftTestingTests {
    @Test func `Interop mode should not be set`() {
        let interopMode = ProcessInfo.processInfo.environment["SWIFT_TESTING_XCTEST_INTEROP_MODE"]
        // Normally the default should be set here, but this is run in a workspace with tools-version < 6.4
        #expect(interopMode == nil)
    }
}
