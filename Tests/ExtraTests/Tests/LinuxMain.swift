import XCTest

import ExtraTests

var tests = [XCTestCaseEntry]()
tests += ExtraTests.__allTests()

XCTMain(tests)
