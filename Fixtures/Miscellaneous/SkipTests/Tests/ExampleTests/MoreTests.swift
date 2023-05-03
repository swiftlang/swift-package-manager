import XCTest
@testable import Example

class MoreTests: XCTestCase {
    func testExample3() {
      XCTAssertEqual(Example().text, "Hello, World!")
    }

    func testExample4() {
        XCTAssertEqual(Example().bool, false)
    }
}
