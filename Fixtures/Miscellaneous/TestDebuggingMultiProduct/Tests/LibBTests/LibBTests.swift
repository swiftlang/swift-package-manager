import XCTest
import Testing
@testable import LibB

final class LibBXCTests: XCTestCase {
    func testGreet() {
        let lib = LibB()
        XCTAssertEqual(lib.greet(), "Hello from LibB")
    }
}

@Test("LibB greeting works")
func libBGreeting() {
    let lib = LibB()
    #expect(lib.greet() == "Hello from LibB")
}
