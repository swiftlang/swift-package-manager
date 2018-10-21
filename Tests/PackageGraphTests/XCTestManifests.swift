#if !canImport(ObjectiveC)
import XCTest

extension DependencyResolverTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__DependencyResolverTests = [
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
        ("testRevisionConstraint2", testRevisionConstraint2),
        ("testRevisionConstraint", testRevisionConstraint),
        ("testUnversionedConstraint", testUnversionedConstraint),
        ("testVersionAssignment", testVersionAssignment),
        ("testVersionSetSpecifier", testVersionSetSpecifier),
    ]
}

extension PackageGraphTests {
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PackageGraphTests = [
        ("testBasic", testBasic),
        ("testCycle2", testCycle2),
        ("testCycle", testCycle),
        ("testDuplicateInterPackageTargetNames", testDuplicateInterPackageTargetNames),
        ("testDuplicateModules", testDuplicateModules),
        ("testDuplicateProducts", testDuplicateProducts),
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
    // DO NOT MODIFY: This is autogenerated, use: 
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__RepositoryPackageContainerProviderTests = [
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
        testCase(DependencyResolverTests.__allTests__DependencyResolverTests),
        testCase(PackageGraphTests.__allTests__PackageGraphTests),
        testCase(RepositoryPackageContainerProviderTests.__allTests__RepositoryPackageContainerProviderTests),
    ]
}
#endif
