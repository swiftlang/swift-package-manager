import XCTest

import ComplexPackageTests

var tests = [XCTestCaseEntry]()
tests += ComplexPackageTests.allTests()
XCTMain(tests)
