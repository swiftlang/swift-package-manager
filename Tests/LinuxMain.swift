/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest

import BasicTests
import BuildTests
import CommandsTests
import FunctionalTests
import POSIXTests
import PackageDescriptionTests
import PackageGraphTests
import PackageLoadingTests
import PackageModelTests
import SourceControlTests
import UtilityTests
import WorkspaceTests 
import XcodeprojTests

var tests = [XCTestCaseEntry]()
tests += BasicTests.allTests()
tests += BuildTests.allTests()
tests += CommandsTests.allTests()
tests += FunctionalTests.allTests()
tests += POSIXTests.allTests()
tests += PackageDescriptionTests.allTests()
tests += PackageGraphTests.allTests()
tests += PackageLoadingTests.allTests()
tests += PackageModelTests.allTests()
tests += SourceControlTests.allTests()
tests += UtilityTests.allTests()
tests += WorkspaceTests.allTests()
tests += XcodeprojTests.allTests()
XCTMain(tests)
