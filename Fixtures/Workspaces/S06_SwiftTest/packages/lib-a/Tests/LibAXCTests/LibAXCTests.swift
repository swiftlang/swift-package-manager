import XCTest
@testable import LibA

final class LibAXCTests: XCTestCase {
    func testLibAGreeting() {
        XCTAssertEqual(libAGreeting(), "Hello from lib-a")
    }
}
