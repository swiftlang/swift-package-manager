import _InternalTestSupport
import XCTest

fileprivate final class TestGetNumberOfMatches: XCTestCase {
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
