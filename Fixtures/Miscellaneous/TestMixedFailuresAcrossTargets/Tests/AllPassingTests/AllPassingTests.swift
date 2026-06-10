import XCTest
import Testing

final class AllPassingXCTests: XCTestCase {
    func testPassingXCTest() {
        XCTAssertTrue(true)
    }
}

@Test func passingSwiftTest() {
    #expect(true)
}
