
// we want to generate this.
// read the AST and generate it
// ticket:

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
    DependencyResolutionTestCase(),
    FileTests(),
    GetTests(),
    GitTests(),
    InvalidLayoutsTestCase(),
	ManifestTests(),
    MiscellaneousTestCase(),
    ManifestParsertest.PackageTests(),
	ModuleTests(),
    PackageTypetest.PackageTests(),
	PathTests(),
	RelativePathTests(),
	ResourcesTests(),
	ShellTests(),
	StatTests(),
	StringTests(),
	TOMLTests(),
	URLTests(),
	ValidLayoutsTestCase(),
	VersionGraphTests(),
	VersionTests(),
	WalkTests(),
    ModuleMapsTestCase(),
    DescribeTests(),
])
