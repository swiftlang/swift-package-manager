import XCTest

import CodeCoverageTests

var tests = [XCTestCaseEntry]()
tests += CodeCoverageTests.allTests()
XCTMain(tests)