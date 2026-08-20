import XCTest
import MyLibrary

final class SecondTests: XCTestCase {
    func testGreeting() {
        XCTAssertEqual(greeting(), "hello")
    }
}
