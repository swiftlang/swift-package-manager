import XCTest

@testable import ModuleA

class BarTests: XCTestCase {
    func testSuccess() {
    }
}

extension BarTests {
    static var allTests: [(String, BarTests -> () throws -> Void)] {
        return [
            ("testSuccess", testSuccess),
        ]
    }
}
