import XCTest

class FooTests: XCTestCase {
    func testSuccess() {
    }
}

#if os(Linux)
extension FooTests: XCTestCaseProvider {
    var allTests: [(String, () throws -> Void)] {
        return [
            ("testSuccess", testSuccess),
        ]
    }
}
#endif
