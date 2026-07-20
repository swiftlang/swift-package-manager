import XCTest

import MacroDef
@testable import MacroImpl

final class MacroImplTests: XCTestCase {
    func testMacroPluginType() {
        _ = MacroPlugin.self
    }

    func testStringify() {
        let result = #stringify(42)
        XCTAssertEqual(result, "expanded")
    }
}
