#if !os(macOS)
import XCTest

extension InitTests {
    static let __allTests = [
        ("testInitPackageEmpty", testInitPackageEmpty),
        ("testInitPackageExecutable", testInitPackageExecutable),
        ("testInitPackageLibrary", testInitPackageLibrary),
        ("testInitPackageNonc99Directory", testInitPackageNonc99Directory),
        ("testInitPackageSystemModule", testInitPackageSystemModule),
        ("testNonC99NameExecutablePackage", testNonC99NameExecutablePackage),
    ]
}

extension PinsStoreTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testLoadingSchema1", testLoadingSchema1),
    ]
}

extension ToolsVersionWriterTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testZeroedPatchVersion", testZeroedPatchVersion),
    ]
}

extension WorkspaceTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testBranchAndRevision", testBranchAndRevision),
        ("testCanResolveWithIncompatiblePins", testCanResolveWithIncompatiblePins),
        ("testCanUneditRemovedDependencies", testCanUneditRemovedDependencies),
        ("testChangeOneDependency", testChangeOneDependency),
        ("testCleanAndReset", testCleanAndReset),
        ("testDeletedCheckoutDirectory", testDeletedCheckoutDirectory),
        ("testDependencyManifestLoading", testDependencyManifestLoading),
        ("testDependencyResolutionWithEdit", testDependencyResolutionWithEdit),
        ("testEditDependency", testEditDependency),
        ("testGraphData", testGraphData),
        ("testGraphRootDependencies", testGraphRootDependencies),
        ("testInterpreterFlags", testInterpreterFlags),
        ("testIsResolutionRequired", testIsResolutionRequired),
        ("testLoadingRootManifests", testLoadingRootManifests),
        ("testLocalDependencyBasics", testLocalDependencyBasics),
        ("testLocalDependencyTransitive", testLocalDependencyTransitive),
        ("testLocalDependencyWithPackageUpdate", testLocalDependencyWithPackageUpdate),
        ("testLocalLocalSwitch", testLocalLocalSwitch),
        ("testLocalVersionSwitch", testLocalVersionSwitch),
        ("testMissingEditCanRestoreOriginalCheckout", testMissingEditCanRestoreOriginalCheckout),
        ("testMultipleRootPackages", testMultipleRootPackages),
        ("testResolutionFailureWithEditedDependency", testResolutionFailureWithEditedDependency),
        ("testResolve", testResolve),
        ("testResolverCanHaveError", testResolverCanHaveError),
        ("testRevisionVersionSwitch", testRevisionVersionSwitch),
        ("testRootAsDependency1", testRootAsDependency1),
        ("testRootAsDependency2", testRootAsDependency2),
        ("testSkipUpdate", testSkipUpdate),
        ("testToolsVersionRootPackages", testToolsVersionRootPackages),
        ("testUpdate", testUpdate),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(InitTests.__allTests),
        testCase(PinsStoreTests.__allTests),
        testCase(ToolsVersionWriterTests.__allTests),
        testCase(WorkspaceTests.__allTests),
    ]
}
#endif
