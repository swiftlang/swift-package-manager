#if !os(macOS)
import XCTest

extension EnvTests {
    static let __allTests = [
        ("testGet", testGet),
        ("testSet", testSet),
        ("testWithCustomEnv", testWithCustomEnv),
    ]
}

extension PosixTests {
    static let __allTests = [
        ("testRename", testRename),
    ]
}

extension ReaddirTests {
    static let __allTests = [
        ("testName", testName),
    ]
}

extension UsleepTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(EnvTests.__allTests),
        testCase(PosixTests.__allTests),
        testCase(ReaddirTests.__allTests),
        testCase(UsleepTests.__allTests),
    ]
}
#endif
