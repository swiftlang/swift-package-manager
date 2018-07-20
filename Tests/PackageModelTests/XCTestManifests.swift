#if !os(macOS)
import XCTest

extension PackageModelTests {
    static let __allTests = [
        ("testProductTypeCodable", testProductTypeCodable),
    ]
}

extension SwiftLanguageVersionTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testComparison", testComparison),
    ]
}

extension TargetDependencyTests {
    static let __allTests = [
        ("test1", test1),
        ("test2", test2),
        ("test3", test3),
        ("test4", test4),
        ("test5", test5),
        ("test6", test6),
    ]
}

extension ToolsVersionTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(PackageModelTests.__allTests),
        testCase(SwiftLanguageVersionTests.__allTests),
        testCase(TargetDependencyTests.__allTests),
        testCase(ToolsVersionTests.__allTests),
    ]
}
#endif
