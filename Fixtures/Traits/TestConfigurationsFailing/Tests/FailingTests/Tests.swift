import XCTest

final class FailingTests: XCTestCase {
    func testFails() {
        XCTFail("intentional failure")
    }
}
