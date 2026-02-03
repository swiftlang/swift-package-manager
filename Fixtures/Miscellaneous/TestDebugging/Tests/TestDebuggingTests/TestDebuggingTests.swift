import XCTest
import Testing
@testable import TestDebugging

// MARK: - XCTest Suite
final class XCTestCalculatorTests: XCTestCase {

    func testAdditionPasses() {
        let calculator = Calculator()
        let result = calculator.add(2, 3)
        XCTAssertEqual(result, 5, "Addition should return 5 for 2 + 3")
    }

    func testSubtractionFails() {
        let calculator = Calculator()
        let result = calculator.subtract(5, 3)
        XCTAssertEqual(result, 3, "This test is designed to fail - subtraction 5 - 3 should equal 2, not 3")
    }
}

// MARK: - Swift Testing Suite
@Test("Calculator Addition Works Correctly")
func calculatorAdditionPasses() {
    let calculator = Calculator()
    let result = calculator.add(4, 6)
    #expect(result == 10, "Addition should return 10 for 4 + 6")
}

@Test("Calculator Boolean Check Fails")
func calculatorBooleanFails() {
    let calculator = Calculator()
    let result = calculator.purposelyFail()
    #expect(result == true, "This test is designed to fail - purposelyFail() should return false, not true")
}