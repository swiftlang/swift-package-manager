import XCTest
import Testing

final class FailingXCTests: XCTestCase {
    func testFailingXCTest() {
        XCTAssertTrue(false, "Intentional XCTest failure")
    }
}

@Test func passingSwiftTest() {
    #expect(true)
}
