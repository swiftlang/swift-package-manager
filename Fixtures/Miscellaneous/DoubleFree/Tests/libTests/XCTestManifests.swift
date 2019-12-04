import XCTest

extension libTests {
    static let __allTests = [
        ("testDoubleFree", testDoubleFree),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(libTests.__allTests),
    ]
}
#endif
