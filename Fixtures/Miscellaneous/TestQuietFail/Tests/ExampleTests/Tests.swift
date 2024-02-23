import XCTest
@testable import Example

class SomeTests: XCTestCase {
    func testFail1() {
        XCTAssertEqual(Example().text, "hello, failure")
    }
    
    func testFail2() {
        XCTAssertEqual(Example().bool, true)
    }
}
