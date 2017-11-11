import XCTest
import BadCode

class BadCodeTests: XCTestCase {

    func testExecuteBadSwift() {
        badSwift()
        XCTAssertEqual("ok", "ok")
    }

    func testExecuteBadSwiftWithBadC() {
        badSwiftWithBadC()
        XCTAssertEqual("ok", "ok")
    }


    static var allTests = [
        ("testExecuteBadSwift", testExecuteBadSwift),
        ("testExecuteBadSwiftWithBadC", testExecuteBadSwiftWithBadC),
    ]
}
