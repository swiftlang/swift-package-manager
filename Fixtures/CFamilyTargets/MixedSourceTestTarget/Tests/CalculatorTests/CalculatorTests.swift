import XCTest
import Calculator

final class CalculatorTests: XCTestCase {
    func testLibraryUnderTest() {
        XCTAssertEqual(square(4), 16)
    }

    func testOwnCHelper() {

        XCTAssertEqual(test_c_helper(), 7)
    }
}
