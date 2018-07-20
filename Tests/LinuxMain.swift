import XCTest

import UtilityTests
import BasicTests
import BuildTests
import CommandsTests
import FunctionalTests
import PackageGraphTests
import POSIXTests
import XcodeprojTests
import SourceControlTests
import WorkspaceTests
import PackageDescription4Tests
import PackageLoadingTests
import PackageModelTests
import TestSupportTests

var tests = [XCTestCaseEntry]()
tests += UtilityTests.__allTests()
tests += BasicTests.__allTests()
tests += BuildTests.__allTests()
tests += CommandsTests.__allTests()
tests += FunctionalTests.__allTests()
tests += PackageGraphTests.__allTests()
tests += POSIXTests.__allTests()
tests += XcodeprojTests.__allTests()
tests += SourceControlTests.__allTests()
tests += WorkspaceTests.__allTests()
tests += PackageDescription4Tests.__allTests()
tests += PackageLoadingTests.__allTests()
tests += PackageModelTests.__allTests()
tests += TestSupportTests.__allTests()

XCTMain(tests)
