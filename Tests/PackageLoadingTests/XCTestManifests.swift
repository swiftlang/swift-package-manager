#if !os(macOS)
import XCTest

extension ModuleMapGeneration {
    static let __allTests = [
        ("testModuleNameDirAndHeaderInInclude", testModuleNameDirAndHeaderInInclude),
        ("testModuleNameHeaderInInclude", testModuleNameHeaderInInclude),
        ("testOtherCases", testOtherCases),
        ("testUnsupportedLayouts", testUnsupportedLayouts),
        ("testWarnings", testWarnings),
    ]
}

extension PackageBuilderTests {
    static let __allTests = [
        ("testBadExecutableProductDecl", testBadExecutableProductDecl),
        ("testBrokenSymlink", testBrokenSymlink),
        ("testCInTests", testCInTests),
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testCustomTargetDependencies", testCustomTargetDependencies),
        ("testCustomTargetPaths", testCustomTargetPaths),
        ("testCustomTargetPathsOverlap", testCustomTargetPathsOverlap),
        ("testDeclaredExecutableProducts", testDeclaredExecutableProducts),
        ("testDotFilesAreIgnored", testDotFilesAreIgnored),
        ("testDuplicateProducts", testDuplicateProducts),
        ("testDuplicateTargets", testDuplicateTargets),
        ("testExcludes", testExcludes),
        ("testExecutableAsADep", testExecutableAsADep),
        ("testInvalidManifestConfigForNonSystemModules", testInvalidManifestConfigForNonSystemModules),
        ("testLinuxMain", testLinuxMain),
        ("testLinuxMainError", testLinuxMainError),
        ("testLinuxMainSearch", testLinuxMainSearch),
        ("testManifestTargetDeclErrors", testManifestTargetDeclErrors),
        ("testMixedSources", testMixedSources),
        ("testModuleMapLayout", testModuleMapLayout),
        ("testMultipleTestProducts", testMultipleTestProducts),
        ("testPredefinedTargetSearchError", testPredefinedTargetSearchError),
        ("testPublicHeadersPath", testPublicHeadersPath),
        ("testResolvesSystemModulePackage", testResolvesSystemModulePackage),
        ("testSpecialTargetDir", testSpecialTargetDir),
        ("testSystemLibraryTarget", testSystemLibraryTarget),
        ("testSystemLibraryTargetDiagnostics", testSystemLibraryTargetDiagnostics),
        ("testSystemPackageDeclaresTargetsDiagnostic", testSystemPackageDeclaresTargetsDiagnostic),
        ("testTargetDependencies", testTargetDependencies),
        ("testTestsLayoutsv4", testTestsLayoutsv4),
        ("testValidSources", testValidSources),
        ("testVersionSpecificManifests", testVersionSpecificManifests),
    ]
}

extension PackageDescription4LoadingTests {
    static let __allTests = [
        ("testCompatibleSwiftVersions", testCompatibleSwiftVersions),
        ("testCTarget", testCTarget),
        ("testLanguageStandards", testLanguageStandards),
        ("testManiestVersionToToolsVersion", testManiestVersionToToolsVersion),
        ("testManifestWithWarnings", testManifestWithWarnings),
        ("testPackageDependencies", testPackageDependencies),
        ("testProducts", testProducts),
        ("testSystemPackage", testSystemPackage),
        ("testTargetDependencies", testTargetDependencies),
        ("testTargetProperties", testTargetProperties),
        ("testTrivial", testTrivial),
        ("testUnavailableAPIs", testUnavailableAPIs),
    ]
}

extension PackageDescription4_2LoadingTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testCaching", testCaching),
        ("testDuplicateDependencyDecl", testDuplicateDependencyDecl),
        ("testPackageDependencies", testPackageDependencies),
        ("testRuntimeManifestErrors", testRuntimeManifestErrors),
        ("testSwiftLanguageVersions", testSwiftLanguageVersions),
        ("testSystemLibraryTargets", testSystemLibraryTargets),
        ("testVersionSpecificLoading", testVersionSpecificLoading),
    ]
}

extension PkgConfigTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testDependencies", testDependencies),
    ]
}

extension PkgConfigWhitelistTests {
    static let __allTests = [
        ("testFlagsWithInvalidFlags", testFlagsWithInvalidFlags),
        ("testFlagsWithValueInNextFlag", testFlagsWithValueInNextFlag),
        ("testRemoveDefaultFlags", testRemoveDefaultFlags),
        ("testSimpleFlags", testSimpleFlags),
    ]
}

extension ToolsVersionLoaderTests {
    static let __allTests = [
        ("testBasics", testBasics),
        ("testNonMatching", testNonMatching),
        ("testVersionSpecificManifest", testVersionSpecificManifest),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ModuleMapGeneration.__allTests),
        testCase(PackageBuilderTests.__allTests),
        testCase(PackageDescription4LoadingTests.__allTests),
        testCase(PackageDescription4_2LoadingTests.__allTests),
        testCase(PkgConfigTests.__allTests),
        testCase(PkgConfigWhitelistTests.__allTests),
        testCase(ToolsVersionLoaderTests.__allTests),
    ]
}
#endif
