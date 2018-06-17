import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(libgit2Tests.allTests),
    ]
}
#endif
