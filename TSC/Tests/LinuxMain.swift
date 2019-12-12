import XCTest

import TSCBasicTests
import TSCTestSupportTests
import TSCUtilityTests

var tests = [XCTestCaseEntry]()
tests += TSCBasicTests.__allTests()
tests += TSCTestSupportTests.__allTests()
tests += TSCUtilityTests.__allTests()

XCTMain(tests)
