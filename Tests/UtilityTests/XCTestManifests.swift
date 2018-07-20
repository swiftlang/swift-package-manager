#if !os(macOS)
import XCTest

extension ArgumentParserTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testBinderThrows", testBinderThrows),
        ("testBoolParsing", testBoolParsing),
        ("testErrors", testErrors),
        ("testIntParsing", testIntParsing),
        ("testOptionalPositionalArg", testOptionalPositionalArg),
        ("testOptions", testOptions),
        ("testPathArgument", testPathArgument),
        ("testRemainingStrategy", testRemainingStrategy),
        ("testShellCompletionGeneration", testShellCompletionGeneration),
        ("testSubparser", testSubparser),
        ("testSubparserBinder", testSubparserBinder),
        ("testSubsubparser", testSubsubparser),
        ("testUpToNextOptionStrategy", testUpToNextOptionStrategy),
    ]
}

extension CollectionTests {
    static let __allTests = [
        ("testSplitAround", testSplitAround),
    ]
}

extension InterruptHandlerTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension PkgConfigParserTests {
    static let __allTests = [
        ("testCustomPcFileSearchPath", testCustomPcFileSearchPath),
        ("testEmptyCFlags", testEmptyCFlags),
        ("testEscapedSpaces", testEscapedSpaces),
        ("testGTK3PCFile", testGTK3PCFile),
        ("testUnevenQuotes", testUnevenQuotes),
        ("testUnresolvablePCFile", testUnresolvablePCFile),
        ("testVariableinDependency", testVariableinDependency),
    ]
}

extension ProgressBarTests {
    static let __allTests = [
        ("testProgressBar", testProgressBar),
    ]
}

extension SimplePersistenceTests {
    static let __allTests = [
        ("testBackwardsCompatibleStateFile", testBackwardsCompatibleStateFile),
        ("testBasics", testBasics),
        ("testCanLoadFromOldSchema", testCanLoadFromOldSchema),
    ]
}

extension StringConversionTests {
    static let __allTests = [
        ("testManglingToBundleIdentifier", testManglingToBundleIdentifier),
        ("testManglingToC99ExtendedIdentifier", testManglingToC99ExtendedIdentifier),
    ]
}

extension StringTests {
    static let __allTests = [
        ("testChuzzle", testChuzzle),
        ("testEmptyChomp", testEmptyChomp),
        ("testSeparatorChomp", testSeparatorChomp),
        ("testSplitAround", testSplitAround),
        ("testTrailingChomp", testTrailingChomp),
    ]
}

extension URLTests {
    static let __allTests = [
        ("testSchema", testSchema),
    ]
}

extension VersionTests {
    static let __allTests = [
        ("testComparable", testComparable),
        ("testContains", testContains),
        ("testDescription", testDescription),
        ("testEquality", testEquality),
        ("testFromString", testFromString),
        ("testHashable", testHashable),
        ("testOrder", testOrder),
        ("testRange", testRange),
    ]
}

extension miscTests {
    static let __allTests = [
        ("testClangVersionOutput", testClangVersionOutput),
        ("testVersion", testVersion),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ArgumentParserTests.__allTests),
        testCase(CollectionTests.__allTests),
        testCase(InterruptHandlerTests.__allTests),
        testCase(PkgConfigParserTests.__allTests),
        testCase(ProgressBarTests.__allTests),
        testCase(SimplePersistenceTests.__allTests),
        testCase(StringConversionTests.__allTests),
        testCase(StringTests.__allTests),
        testCase(URLTests.__allTests),
        testCase(VersionTests.__allTests),
        testCase(miscTests.__allTests),
    ]
}
#endif
