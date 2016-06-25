/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import BasicTestSuite
import BuildTestSuite
import FunctionalTestSuite
import GetTestSuite
import POSIXTestSuite
import PackageDescriptionTestSuite
import PackageGraphTestSuite
import PackageLoadingTestSuite
import PackageModelTestSuite
import SourceControlTestSuite
import UtilityTestSuite

var tests = [XCTestCaseEntry]()
tests += BasicTestSuite.allTests()
tests += BuildTestSuite.allTests()
tests += FunctionalTestSuite.allTests()
tests += GetTestSuite.allTests()
tests += POSIXTestSuite.allTests()
tests += PackageDescriptionTestSuite.allTests()
tests += PackageGraphTestSuite.allTests()
tests += PackageLoadingTestSuite.allTests()
tests += PackageModelTestSuite.allTests()
tests += SourceControlTestSuite.allTests()
tests += UtilityTestSuite.allTests()
XCTMain(tests)
