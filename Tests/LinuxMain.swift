import XCTest

import BasicTests
import BuildTests
import CommandsTests
import FunctionalTests
import PackageDescription4Tests
import PackageGraphTests
import PackageLoadingTests
import PackageModelTests
import SourceControlTests
import TestSupportTests
import UtilityTests
import WorkspaceTests
import XcodeprojTests

var tests = [XCTestCaseEntry]()
tests += BasicTests.__allTests()
tests += BuildTests.__allTests()
tests += CommandsTests.__allTests()
tests += FunctionalTests.__allTests()
tests += PackageDescription4Tests.__allTests()
tests += PackageGraphTests.__allTests()
tests += PackageLoadingTests.__allTests()
tests += PackageModelTests.__allTests()
tests += SourceControlTests.__allTests()
tests += TestSupportTests.__allTests()
tests += UtilityTests.__allTests()
tests += WorkspaceTests.__allTests()
tests += XcodeprojTests.__allTests()

XCTMain(tests)
