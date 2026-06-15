import XCTest

import MacroDef

final class MinimalMacroPackageTests: XCTestCase {
    func testStringify() {
        let result = #stringify(42)
        XCTAssertEqual(result, "expanded")
    }
}
