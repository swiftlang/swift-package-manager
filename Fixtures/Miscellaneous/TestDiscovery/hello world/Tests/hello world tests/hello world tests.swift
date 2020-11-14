import XCTest
@testable import hello_world

final class hello_worldTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(hello_world().text, "Hello, World!")
    }
}
