import XCTest
@testable import TestFailures

final class TestFailuresTests: XCTestCase {
    func testExample() throws {
        XCTAssertFalse(true, "Purposely failing & validating XML espace \"'<>")
    }
}

