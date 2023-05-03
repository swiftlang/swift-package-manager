import XCTest
@testable import Example

class SomeTests: XCTestCase {
    func testExample1() {
        XCTAssertEqual(Example().text, "Hello, World!")
    }

    func testExample2() {
        XCTAssertEqual(Example().bool, false)
    }
}
