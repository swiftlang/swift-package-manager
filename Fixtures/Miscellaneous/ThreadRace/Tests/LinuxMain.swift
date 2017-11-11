import XCTest

import libTests

var tests = [XCTestCaseEntry]()
tests += libTests.__allTests()

XCTMain(tests)
