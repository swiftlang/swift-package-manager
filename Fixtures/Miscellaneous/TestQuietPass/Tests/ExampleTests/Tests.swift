import XCTest
@testable import Example

class SomeTests: XCTestCase {
    func testPass1() {
        XCTAssertEqual(Example().text, "Hello, World!")
    }
    
    func testPass2() {
        XCTAssertEqual(Example().bool, false)
    }
}
