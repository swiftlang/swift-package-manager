
// we want to generate this.
// read the AST and generate it
// ticket:

import XCTest

import BasicTestSuite
import BuildTestSuite
import FunctionalTestSuite
import GetTestSuite
import ManifestSerializerTestSuite
import OptionsParserTestSuite
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
tests += OptionsParserTestSuite.allTests()
tests += PackageDescriptionTestSuite.allTests()
tests += PackageTypeTestSuite.allTests()
tests += PkgConfigTestSuite.allTests()
tests += TransmuteTestSuite.allTests()
tests += UtilityTestSuite.allTests()
XCTMain(tests)
