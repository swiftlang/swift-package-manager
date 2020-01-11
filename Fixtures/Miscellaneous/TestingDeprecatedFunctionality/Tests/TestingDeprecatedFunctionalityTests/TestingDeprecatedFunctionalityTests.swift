import XCTest
@testable import TestingDeprecatedFunctionality

final class TestingDeprecatedFunctionalityTests: XCTestCase {
    @available(*, deprecated, message: "Just deprecated to allow deprecated tests (which test deprecated functionality) without warnings")
    func testDeprecatedFunctionality() {
        XCTAssertEqual(TestingDeprecatedFunctionality().text, "Deprecated text.")
    }
}
