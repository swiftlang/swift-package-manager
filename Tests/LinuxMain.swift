import XCTest

import BuildTests
import CommandsTests
import FunctionalTests
import PackageDescription4Tests
import PackageGraphTests
import PackageLoadingTests
import PackageModelTests
import SourceControlTests
import WorkspaceTests
import XCBuildSupportTests
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
tests += WorkspaceTests.__allTests()
tests += XCBuildSupportTests.__allTests()
tests += XcodeprojTests.__allTests()

XCTMain(tests)
