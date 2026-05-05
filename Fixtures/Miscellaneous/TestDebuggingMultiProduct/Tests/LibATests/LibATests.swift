import XCTest
import Testing
@testable import LibA

final class LibAXCTests: XCTestCase {
    func testGreet() {
        let lib = LibA()
        XCTAssertEqual(lib.greet(), "Hello from LibA")
    }
}

@Test("LibA greeting works")
func libAGreeting() {
    let lib = LibA()
    #expect(lib.greet() == "Hello from LibA")
}
