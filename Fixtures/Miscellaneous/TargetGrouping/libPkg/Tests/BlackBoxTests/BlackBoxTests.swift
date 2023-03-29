import MainLib
import XCTest

class BlackBoxTests: XCTestCase {
    func testBlackBox() {
        let x = publicFunc()
        XCTAssertTrue(x > 0)
    }
}
