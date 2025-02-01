import SPMBuildCore
import _InternalTestSupport
import XCTest

final class TestGetNumberOfMatches: XCTestCase {
    func testEmptyStringMatchesOnEmptyStringZeroTimes() {
        let matchOn = ""
        let value = ""
        let expectedNumMatches = 0

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testEmptyStringMatchesOnNonEmptySingleLineStringZeroTimes() {
        let matchOn = ""
        let value = "This is a non-empty string"
        let expectedNumMatches = 0

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testEmptyStringMatchesOnNonEmptyMultilineStringWithNeLineCharacterZeroTimes() {
        let matchOn = ""
        let value = "This is a non-empty string\nThis is the second line"
        let expectedNumMatches = 0

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testEmptyStringMatchesOnNonEmptyMultilineStringUsingTripleDoubleQuotesZeroTimes() {
        let matchOn = ""
        let value = """
        This is a non-empty string
        This is the second line
        This is the third line
        """
        let expectedNumMatches = 0

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testNonEmptyStringMatchesOnEmptyStringReturnsZero() {
        let matchOn = """
        This is a non-empty string
        This is the second line
        This is the third line
        """
        let value = ""
        let expectedNumMatches = 0

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testfatalErrorMatchesOnMultiLineWithTwoOccurencesReturnsTwo() {
        let matchOn = "error: fatalError"
        let value = """
        > swift test                                                                                          25/10/24 10:44:14
        Building for debugging...
        /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                let y = 1 / x
                        ^
        error: fatalError

        error: fatalError
        """
        let expectedNumMatches = 2

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testfatalErrorWithLeadingNewLineMatchesOnMultiLineWithTwoOccurencesReturnsTwo() {
        let matchOn = "\nerror: fatalError"
        let value = """
        > swift test                                                                                          25/10/24 10:44:14
        Building for debugging...
        /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                let y = 1 / x
                        ^
        error: fatalError

        error: fatalError
        """
        let expectedNumMatches = 2

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }

    func testfatalErrorWithLeadingAndTrailingNewLineMatchesOnMultiLineWithOneOccurencesReturnsOne() {
        let matchOn = "\nerror: fatalError\n"
        let value = """
        > swift test                                                                                          25/10/24 10:44:14
        Building for debugging...
        /Users/arandomuser/Documents/personal/repro-swiftpm-6605/Tests/repro-swiftpm-6605Tests/repro_swiftpm_6605Tests.swift:7:19: error: division by zero
                let y = 1 / x
                        ^
        error: fatalError

        error: fatalError
        """
        let expectedNumMatches = 1

        let actual = getNumberOfMatches(of: matchOn, in: value)

        XCTAssertEqual(actual, expectedNumMatches, "Actual is not as expected")
    }
}

final class TestGetBuildSystemArgs: XCTestCase {
    func testNilArgumentReturnsEmptyArray() {
        let expected: [String] = []
        let inputUnderTest: BuildSystemProvider.Kind?  = nil

        let actual = getBuildSystemArgs(for: inputUnderTest)

        XCTAssertEqual(actual, expected, "Actual is not as expected")
    }

    private func testValidArgumentsReturnsCorrectCommandLineArguments(_ inputValue: BuildSystemProvider.Kind) {
        let expected = [
            "--build-system",
            "\(inputValue)"
        ]

        let actual = getBuildSystemArgs(for: inputValue)

        XCTAssertEqual(actual, expected, "Actual is not as expected")
    }

    private func testNativeReturnExpectedArray() {
        self.testValidArgumentsReturnsCorrectCommandLineArguments(.native)
    }

    private func testNextReturnExpectedArray() {
        self.testValidArgumentsReturnsCorrectCommandLineArguments(.swiftbuild)
    }

    private func testXcodeReturnExpectedArray() {
        self.testValidArgumentsReturnsCorrectCommandLineArguments(.xcode)
    }
}
