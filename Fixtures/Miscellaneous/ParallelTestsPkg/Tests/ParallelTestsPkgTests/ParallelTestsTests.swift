import XCTest
@testable import ParallelTestsPkg

class ParallelTestsTests: XCTestCase {

    func testExample1() {
        XCTAssertEqual(ParallelTests().text, "Hello, World!")
    }

    func testExample2() {
        XCTAssertEqual(ParallelTests().bool, false)
    }

    static var allTests : [(String, (ParallelTestsTests) -> () throws -> Void)] {
        return [
            ("testExample1", testExample1),
            ("testExample2", testExample2),
        ]
    }
}
