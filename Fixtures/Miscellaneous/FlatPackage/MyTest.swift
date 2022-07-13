import XCTest
@testable import MyExec

final class MyTest: XCTestCase {
    func testExample() throws {
        XCTAssertEqual(MyExec().text, "Hello, World!")
    }
}
