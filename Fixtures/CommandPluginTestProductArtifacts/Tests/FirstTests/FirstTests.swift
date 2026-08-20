import XCTest
import MyLibrary

final class FirstTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual(greeting(), "hello")
    }
}
