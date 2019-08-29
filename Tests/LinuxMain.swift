import XCTest

import BuildTests
import CommandsTests
import FunctionalTests
import PackageDescription4Tests
import PackageGraphTests
import PackageLoadingTests
import PackageModelTests
import SourceControlTests
import TSCBasicTests
import TSCTestSupportTests
import TSCUtilityTests
import WorkspaceTests
import XcodeprojTests

var tests = [XCTestCaseEntry]()
tests += BuildTests.__allTests()
tests += CommandsTests.__allTests()
tests += FunctionalTests.__allTests()
tests += PackageDescription4Tests.__allTests()
tests += PackageGraphTests.__allTests()
tests += PackageLoadingTests.__allTests()
tests += PackageModelTests.__allTests()
tests += SourceControlTests.__allTests()
tests += TSCBasicTests.__allTests()
tests += TSCTestSupportTests.__allTests()
tests += TSCUtilityTests.__allTests()
tests += WorkspaceTests.__allTests()
tests += XcodeprojTests.__allTests()

XCTMain(tests)
