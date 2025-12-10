import XCTest
@testable import TestableExe

final class TestableExeTests: XCTestCase {
    func testExample() throws {
        XCTAssertEqual(GetGreeting1(), "bar\n")
    }
}
