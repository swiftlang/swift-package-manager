import XCTest
@testable import Async

class AsyncTests: XCTestCase {

    func testAsync() async {
    }

    @MainActor func testMainActor() async {
        XCTAssertTrue(Thread.isMainThread)
    }

    func testNotAsync() {
        XCTAssertTrue(Thread.isMainThread)
    }
}
