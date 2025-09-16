import Testing
import XCTest
@testable import Simple

@Test(
    arguments: [
        "Bob",
        "Alice",
        "",
    ]
)
 func testGreet(
    name: String
 ) async throws {
    let actual = greet(name: name)

    #expect(actual == "Hello, \(name)!")
}

final class SimpleTests: XCTestCase {
    func testExample() throws {
        XCTAssertEqual(libA(), "libA", "Actual is not as expected")
    }
}
