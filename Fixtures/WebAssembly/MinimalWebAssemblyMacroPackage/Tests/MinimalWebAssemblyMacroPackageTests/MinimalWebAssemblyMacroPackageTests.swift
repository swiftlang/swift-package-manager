import XCTest

import MacroDef

final class MinimalWebAssemblyMacroPackageTests: XCTestCase {
    func testStringify() {
        let result = #stringify(42)
        XCTAssertEqual(result, "expanded")
    }
}
