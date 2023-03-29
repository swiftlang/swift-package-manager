import MainLib
import XCTest

class TestMainLib: XCTestCase {
    func testMainLib() {
        let x = publicFunc()
        XCTAssertTrue(x > 0)
    }
}
