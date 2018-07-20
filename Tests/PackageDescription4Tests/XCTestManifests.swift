#if !os(macOS)
import XCTest

extension JSONTests {
    static let __allTests = [
        ("testEncoding", testEncoding),
    ]
}

extension VersionTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(JSONTests.__allTests),
        testCase(VersionTests.__allTests),
    ]
}
#endif
