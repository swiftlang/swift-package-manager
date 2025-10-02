import XCTest

final class TestFailuresTests: XCTestCase {
    func testExample() throws {
        XCTAssertFalse(true, "Purposely failing & validating XML espace \"'<>")
    }
}

