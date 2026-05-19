import XCTest
@testable import AppPlaygroundWithTests

final class GreetingTests: XCTestCase {

    /// Test that our greeting is the expected one.
    func testGreeting() throws {
        XCTAssertEqual(GetGreeting(), "Hello")
    }
}
