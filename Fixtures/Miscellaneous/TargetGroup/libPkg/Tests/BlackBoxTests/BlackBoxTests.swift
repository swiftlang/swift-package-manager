import MainLib
import XCTest

class BlackboxTests: XCTestCase {
    func testBlackbox() {
        let x = publicFunc()
        XCTAssertTrue(x > 0)
    }
}
