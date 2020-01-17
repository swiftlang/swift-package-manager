import XCTest

import IntegrationTests

var tests = [XCTestCaseEntry]()
tests += IntegrationTests.__allTests()

XCTMain(tests)
