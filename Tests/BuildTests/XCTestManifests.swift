#if !os(macOS)
import XCTest

extension BuildPlanTests {
    static let __allTests = [
        ("testBasicClangPackage", testBasicClangPackage),
        ("testBasicExtPackages", testBasicExtPackages),
        ("testBasicReleasePackage", testBasicReleasePackage),
        ("testBasicSwiftPackage", testBasicSwiftPackage),
        ("testClangTargets", testClangTargets),
        ("testCLanguageStandard", testCLanguageStandard),
        ("testCModule", testCModule),
        ("testCppModule", testCppModule),
        ("testDynamicProducts", testDynamicProducts),
        ("testExecAsDependency", testExecAsDependency),
        ("testNonReachableProductsAndTargets", testNonReachableProductsAndTargets),
        ("testPkgConfigGenericDiagnostic", testPkgConfigGenericDiagnostic),
        ("testPkgConfigHintDiagnostic", testPkgConfigHintDiagnostic),
        ("testSwiftCMixed", testSwiftCMixed),
        ("testSystemPackageBuildPlan", testSystemPackageBuildPlan),
        ("testTestModule", testTestModule),
    ]
}

extension IncrementalBuildTests {
    static let __allTests = [
        ("testIncrementalSingleModuleCLibraryInSources", testIncrementalSingleModuleCLibraryInSources),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BuildPlanTests.__allTests),
        testCase(IncrementalBuildTests.__allTests),
    ]
}
#endif
