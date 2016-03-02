import XCTest

class FooTests: XCTestCase {
    func testSuccess() {
    }
}

extension FooTests {
    static var allTests: [(String, FooTests -> () throws -> Void)] {
        return [
            ("testSuccess", testSuccess),
        ]
    }
}
