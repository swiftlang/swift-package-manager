import XCTest
import XCTestCaseProvider

XCTMain([
    DependencyResolutionTestCase(),
    InvalidLayoutsTestCase(),
    MiscellaneousTestCase(),
	ValidLayoutsTestCase(),
])
