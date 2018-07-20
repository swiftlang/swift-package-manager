#if !os(macOS)
import XCTest

extension TestSupportTests {
    static let __allTests = [
        ("testAssertMatchStringLists", testAssertMatchStringLists),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(TestSupportTests.__allTests),
    ]
}
#endif
