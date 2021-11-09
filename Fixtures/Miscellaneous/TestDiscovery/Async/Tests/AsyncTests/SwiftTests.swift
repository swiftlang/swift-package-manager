import XCTest
@testable import Async

class AsyncTests: XCTestCase {

    func testAsync() async {
        XCTAssertFalse(Thread.isMainThread)
    }

    @MainActor func testMainActor() async {
        XCTAssertTrue(Thread.isMainThread)
    }

    func testNotAsync() {
        XCTAssertTrue(Thread.isMainThread)
    }
}
