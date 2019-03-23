import XCTest
@testable import GenerateLinuxMain

final class GenerateLinuxMainTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(GenerateLinuxMain().text, "Hello, World!")
    }

    func testAddition() {
        XCTAssertEqual(1 + 1, 2)
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
