import XCTest

@testable import ModuleA

class BarTests: XCTestCase {
    func testSuccess() {
    }
}

#if os(Linux)
extension BarTests: XCTestCaseProvider {
    var allTests: [(String, () throws -> Void)] {
        return [
            ("testSuccess", testSuccess),
        ]
    }
}
#endif

