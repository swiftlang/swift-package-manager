import XCTest
import MixedCore

final class MixedCoreTests: XCTestCase {
    func testSwiftAPI() {

        XCTAssertEqual(MixedCore.add(1, 2), 3)
    }

    func testClangAPI() {

        XCTAssertEqual(c_add(2, 3), 5)
    }
}
