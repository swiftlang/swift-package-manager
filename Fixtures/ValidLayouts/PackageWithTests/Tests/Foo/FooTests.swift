import XCTest

@testable import Foo

class FooTests: XCTestCase {
    func testExample() {
        XCTAssertEqual(Foo().text, "Hello, World!")
    }

    static var allTests = {
        return [
            ("testExample", testExample),
        ]
    }()
}
