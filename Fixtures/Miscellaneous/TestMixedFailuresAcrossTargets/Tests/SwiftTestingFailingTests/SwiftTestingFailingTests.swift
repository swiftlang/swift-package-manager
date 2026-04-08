import XCTest
import Testing

final class PassingXCTests: XCTestCase {
    func testPassingXCTest() {
        XCTAssertTrue(true)
    }
}

@Test func failingSwiftTest() {
    #expect(Bool(false), "Intentional Swift Testing failure")
}
