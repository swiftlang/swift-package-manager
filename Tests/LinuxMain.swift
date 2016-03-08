import XCTest

@testable import Transmutetest
@testable import Utilitytest
@testable import Functionaltest
@testable import Gettest
@testable import ManifestParsertest
@testable import PackageDescriptiontest
@testable import PackageTypetest
@testable import Buildtest

XCTMain([
    testCase(DependencyResolutionTestCase.allTests),
    testCase(FileTests.allTests),
    testCase(GetTests.allTests),
    testCase(GitTests.allTests),
    testCase(InvalidLayoutsTestCase.allTests),
    testCase(ManifestTests.allTests),
    testCase(MiscellaneousTestCase.allTests),
    testCase(ManifestParsertest.PackageTests.allTests),
    testCase(ModuleTests.allTests),
    testCase(PackageDescriptiontest.PackageTests.allTests),
    testCase(PackageTypetest.PackageTests.allTests),
    testCase(PathTests.allTests),
    testCase(RelativePathTests.allTests),
    testCase(ResourcesTests.allTests),
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
])
