import XCTest
@testable import Simple

class SimpleTests: XCTestCase {
    func testHello() {
        Simple().hello()
    }

    @available(*, deprecated, message: "testing deprecated API")
    func testDeprecatedHello() {
        Simple().deprecatedHello()
    }
}
