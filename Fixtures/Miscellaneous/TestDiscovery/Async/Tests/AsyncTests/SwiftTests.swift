import XCTest
@testable import Async

@available(macOS 12.0, *)
class AsyncTests: XCTestCase {

    func testAsync() async {
    }

    func testAsyncThrows() async throws {
    }

    @MainActor func testMainActor() async {
        XCTAssertTrue(Thread.isMainThread)
    }

    func testNotAsync() {
        XCTAssertTrue(Thread.isMainThread)
    }
}
