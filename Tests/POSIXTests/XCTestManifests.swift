#if !canImport(ObjectiveC)
import XCTest

extension EnvTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__EnvTests = [
        ("testGet", testGet),
        ("testSet", testSet),
        ("testWithCustomEnv", testWithCustomEnv),
    ]
}

extension PosixTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PosixTests = [
        ("testRename", testRename),
    ]
}

extension ReaddirTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__ReaddirTests = [
        ("testName", testName),
    ]
}

extension UsleepTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__UsleepTests = [
        ("testBasics", testBasics),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(EnvTests.__allTests__EnvTests),
        testCase(PosixTests.__allTests__PosixTests),
        testCase(ReaddirTests.__allTests__ReaddirTests),
        testCase(UsleepTests.__allTests__UsleepTests),
    ]
}
#endif
