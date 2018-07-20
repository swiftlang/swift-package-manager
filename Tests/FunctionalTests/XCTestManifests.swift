#if !os(macOS)
import XCTest

extension CFamilyTargetTestCase {
    static let __allTests = [
        ("testCanForwardExtraFlagsToClang", testCanForwardExtraFlagsToClang),
        ("testCUsingCAndSwiftDep", testCUsingCAndSwiftDep),
        ("testiquoteDep", testiquoteDep),
        ("testModuleMapGenerationCases", testModuleMapGenerationCases),
        ("testObjectiveCPackageWithTestTarget", testObjectiveCPackageWithTestTarget),
    ]
}

extension DependencyResolutionTests {
    static let __allTests = [
        ("testExternalComplex", testExternalComplex),
        ("testExternalSimple", testExternalSimple),
        ("testInternalComplex", testInternalComplex),
        ("testInternalExecAsDep", testInternalExecAsDep),
        ("testInternalSimple", testInternalSimple),
    ]
}

extension MiscellaneousTestCase {
    static let __allTests = [
        ("testCanBuildMoreThanTwiceWithExternalDependencies", testCanBuildMoreThanTwiceWithExternalDependencies),
        ("testCanKillSubprocessOnSigInt", testCanKillSubprocessOnSigInt),
        ("testCompileFailureExitsGracefully", testCompileFailureExitsGracefully),
        ("testExternalDependencyEdges1", testExternalDependencyEdges1),
        ("testExternalDependencyEdges2", testExternalDependencyEdges2),
        ("testInternalDependencyEdges", testInternalDependencyEdges),
        ("testNoArgumentsExitsWithOne", testNoArgumentsExitsWithOne),
        ("testOverridingSwiftcArguments", testOverridingSwiftcArguments),
        ("testPackageManagerDefineAndXArgs", testPackageManagerDefineAndXArgs),
        ("testPassExactDependenciesToBuildCommand", testPassExactDependenciesToBuildCommand),
        ("testPkgConfigCFamilyTargets", testPkgConfigCFamilyTargets),
        ("testPrintsSelectedDependencyVersion", testPrintsSelectedDependencyVersion),
        ("testReportingErrorFromGitCommand", testReportingErrorFromGitCommand),
        ("testSecondBuildIsNullInModulemapGen", testSecondBuildIsNullInModulemapGen),
        ("testSpaces", testSpaces),
        ("testSwiftTestFilter", testSwiftTestFilter),
        ("testSwiftTestLinuxMainGeneration", testSwiftTestLinuxMainGeneration),
        ("testSwiftTestParallel", testSwiftTestParallel),
    ]
}

extension ModuleMapsTestCase {
    static let __allTests = [
        ("testDirectDependency", testDirectDependency),
        ("testTransitiveDependency", testTransitiveDependency),
    ]
}

extension SwiftPMXCTestHelperTests {
    static let __allTests = [
        ("testBasicXCTestHelper", testBasicXCTestHelper),
    ]
}

extension ToolsVersionTests {
    static let __allTests = [
        ("testToolsVersion", testToolsVersion),
    ]
}

extension VersionSpecificTests {
    static let __allTests = [
        ("testEndToEndResolution", testEndToEndResolution),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(CFamilyTargetTestCase.__allTests),
        testCase(DependencyResolutionTests.__allTests),
        testCase(MiscellaneousTestCase.__allTests),
        testCase(ModuleMapsTestCase.__allTests),
        testCase(SwiftPMXCTestHelperTests.__allTests),
        testCase(ToolsVersionTests.__allTests),
        testCase(VersionSpecificTests.__allTests),
    ]
}
#endif
