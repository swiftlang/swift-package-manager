/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// we want to generate this.
// read the AST and generate it
// ticket:

import XCTest

import BasicTestSuite
import BuildTestSuite
import FunctionalTestSuite
import GetTestSuite
import ManifestSerializerTestSuite
import PackageDescriptionTestSuite
import PackageTypeTestSuite
import PkgConfigTestSuite
import TransmuteTestSuite
import UtilityTestSuite

var tests = [XCTestCaseEntry]()
tests += BasicTestSuite.allTests()
tests += BuildTestSuite.allTests()
tests += FunctionalTestSuite.allTests()
tests += GetTestSuite.allTests()
tests += ManifestSerializerTestSuite.allTests()
tests += PackageDescriptionTestSuite.allTests()
tests += PackageTypeTestSuite.allTests()
tests += PkgConfigTestSuite.allTests()
tests += TransmuteTestSuite.allTests()
tests += UtilityTestSuite.allTests()
XCTMain(tests)
