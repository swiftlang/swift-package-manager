
// we want to generate this.
// read the AST and generate it
// ticket:

import XCTest

@testable import TransmuteTestSuite
@testable import UtilityTestSuite
@testable import FunctionalTestSuite
@testable import GetTestSuite
@testable import ManifestParserTestSuite
@testable import PackageDescriptionTestSuite
@testable import PackageTypeTestSuite
@testable import BuildTestSuite

XCTMain([
    testCase(TestClangModulesTestCase.allTests),
    testCase(DependencyResolutionTestCase.allTests),
    testCase(FileTests.allTests),
    testCase(GetTests.allTests),
    testCase(GitTests.allTests),
    testCase(InvalidLayoutsTestCase.allTests),
    testCase(ManifestTests.allTests),
    testCase(MiscellaneousTestCase.allTests),
    testCase(ManifestParserTestSuite.PackageTests.allTests),
    testCase(ModuleDependencyTests.allTests),
    testCase(ValidSourcesTests.allTests),
    testCase(PrimitiveResolutionTests.allTests),
    testCase(PackageDescriptionTestSuite.PackageTests.allTests),
    testCase(PackageTypeTestSuite.PackageTests.allTests),
    testCase(PathTests.allTests),
    testCase(RelativePathTests.allTests),
    testCase(ShellTests.allTests),
    testCase(StatTests.allTests),
    testCase(StringTests.allTests),
    testCase(TOMLTests.allTests),
    testCase(URLTests.allTests),
    testCase(ValidLayoutsTestCase.allTests),
    testCase(VersionGraphTests.allTests),
    testCase(VersionTests.allTests),
    testCase(WalkTests.allTests),
    testCase(ModuleMapsTestCase.allTests),
    testCase(DescribeTests.allTests),
    testCase(GitUtilityTests.allTests),
    testCase(PackageVersionDataTests.allTests),
])
