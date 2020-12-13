import XCTest
import Exe

final class ExeTestTests: XCTestCase {
    
    func testExample() throws {
        // This is an example of a test case that tries to imports an executable target.
        XCTAssertEqual(Exe.GetGreeting(), "Hello")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
