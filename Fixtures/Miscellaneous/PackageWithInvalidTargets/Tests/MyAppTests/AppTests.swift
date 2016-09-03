import XCTest
@testable import MyApp

class MyAppTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(MyApp().text, "Hello, World!")
    }


    static var allTests : [(String, (MyAppTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
