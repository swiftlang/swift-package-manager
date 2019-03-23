import XCTest

import GenerateLinuxMainTests

var tests = [XCTestCaseEntry]()
tests += GenerateLinuxMainTests.__allTests()

XCTMain(tests)
