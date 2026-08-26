import XCTest
@testable import LibB

final class LibBXCTests: XCTestCase {
    func testLibBGreeting() {
        XCTAssertEqual(libBGreeting(), "Hello from lib-b")
    }
}
