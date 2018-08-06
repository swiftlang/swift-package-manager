#if !os(macOS)
import XCTest

extension PackageModelTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PackageModelTests = [
        ("testProductTypeCodable", testProductTypeCodable),
    ]
}

extension SwiftLanguageVersionTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__SwiftLanguageVersionTests = [
        ("testBasics", testBasics),
        ("testComparison", testComparison),
    ]
}

extension TargetDependencyTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__TargetDependencyTests = [
        ("test1", test1),
        ("test2", test2),
        ("test3", test3),
        ("test4", test4),
        ("test5", test5),
        ("test6", test6),
    ]
}

extension ToolsVersionTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ToolsVersionTests = [
        ("testBasics", testBasics),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(PackageModelTests.__allTests__PackageModelTests),
        testCase(SwiftLanguageVersionTests.__allTests__SwiftLanguageVersionTests),
        testCase(TargetDependencyTests.__allTests__TargetDependencyTests),
        testCase(ToolsVersionTests.__allTests__ToolsVersionTests),
    ]
}
#endif
