#if !os(macOS)
import XCTest

extension DependencyResolverTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testCompleteness", testCompleteness),
        ("testContainerConstraintSet", testContainerConstraintSet),
        ("testDiagnostics", testDiagnostics),
        ("testExactConstraint", testExactConstraint),
        ("testIncompleteMode", testIncompleteMode),
        ("testLazyResolve", testLazyResolve),
        ("testPrereleaseResolve", testPrereleaseResolve),
        ("testResolve", testResolve),
        ("testResolveSubtree", testResolveSubtree),
        ("testRevisionConstraint", testRevisionConstraint),
        ("testUnversionedConstraint", testUnversionedConstraint),
        ("testVersionAssignment", testVersionAssignment),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
    ]
}

extension PackageGraphTests {
    static let __allTests = [
        ("testBasic", testBasic),
        ("testCycle", testCycle),
        ("testDuplicateInterPackageTargetNames", testDuplicateInterPackageTargetNames),
        ("testDuplicateModules", testDuplicateModules),
        ("testEmptyDependency", testEmptyDependency),
        ("testMultipleDuplicateModules", testMultipleDuplicateModules),
        ("testNestedDuplicateModules", testNestedDuplicateModules),
        ("testProductDependencies", testProductDependencies),
        ("testSeveralDuplicateModules", testSeveralDuplicateModules),
        ("testTestTargetDeclInExternalPackage", testTestTargetDeclInExternalPackage),
        ("testUnusedDependency2", testUnusedDependency2),
        ("testUnusedDependency", testUnusedDependency),
    ]
}

extension RepositoryPackageContainerProviderTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testPackageReference", testPackageReference),
        ("testPrereleaseVersions", testPrereleaseVersions),
        ("testSimultaneousVersions", testSimultaneousVersions),
        ("testVersions", testVersions),
        ("testVprefixVersions", testVprefixVersions),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DependencyResolverTests.__allTests),
        testCase(PackageGraphTests.__allTests),
        testCase(RepositoryPackageContainerProviderTests.__allTests),
    ]
}
#endif
