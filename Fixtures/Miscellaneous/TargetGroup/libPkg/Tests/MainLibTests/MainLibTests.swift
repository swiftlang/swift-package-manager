import MainLib
import XCTest

class TestMainLib: XCTestCase {
    func testMainLib() {
        let x = publicFunc()
        let y = packageFunc()
        XCTAssertTrue(x == y)
    }
}
