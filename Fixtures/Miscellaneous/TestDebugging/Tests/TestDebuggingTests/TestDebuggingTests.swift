import XCTest
import Testing
@testable import TestDebugging

final class XCTestCalculatorTests: XCTestCase {
    func testAdditionPasses() {
        let calculator = Calculator()
        let result = calculator.add(2, 3)
        XCTAssertEqual(result, 5, "Addition should return 5 for 2 + 3")
    }
}

@Test
func calculatorAdditionPasses() {
    let calculator = Calculator()
    let result = calculator.add(4, 6)
    #expect(result == 10, "Addition should return 10 for 4 + 6")
}
