import XCTest
@testable import CodeCoverage

final class CodeCoverageTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(CodeCoverage().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
