import XCTest
@testable import Example

class SomeTests: XCTestCase {
    func testPass1() {
        XCTAssertEqual(Example().text, "Hello, World!")
    }
    
    func testPass2() {
        XCTAssertEqual(Example().bool, false)
    }

    func testFail1() {
        XCTAssertEqual(Example().text, "hello, failure")
    }
    
    func testFail2() {
        XCTAssertEqual(Example().bool, true)
    }
}
