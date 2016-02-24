@testable import Foo
import XCTest

class SimpleGetTests: XCTestCase {

    func testGetRequestStatusCode() {
        XCTAssertEqual(ten(), 10)
    }
}

extension SimpleGetTests {
    static var allTests : [(String, SimpleGetTests -> () throws -> Void)]  {
        return [
            ("testGetRequestStatusCode", testGetRequestStatusCode),
        ]
    }
}
