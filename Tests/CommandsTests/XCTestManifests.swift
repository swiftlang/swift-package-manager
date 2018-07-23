#if !os(macOS)
import XCTest

extension BuildToolTests {
    static let __allTests = [
        ("testBinPathAndSymlink", testBinPathAndSymlink),
        ("testLLBuildManifestCachingBasics", testLLBuildManifestCachingBasics),
        ("testNonReachableProductsAndTargetsFunctional", testNonReachableProductsAndTargetsFunctional),
        ("testProductAndTarget", testProductAndTarget),
        ("testSeeAlso", testSeeAlso),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
    ]
}

extension PackageToolTests {
    static let __allTests = [
        ("testDescribe", testDescribe),
        ("testDumpPackage", testDumpPackage),
        ("testInitCustomNameExecutable", testInitCustomNameExecutable),
        ("testInitEmpty", testInitEmpty),
        ("testInitExecutable", testInitExecutable),
        ("testInitLibrary", testInitLibrary),
        ("testPackageClean", testPackageClean),
        ("testPackageEditAndUnedit", testPackageEditAndUnedit),
        ("testPackageReset", testPackageReset),
        ("testPinning", testPinning),
        ("testPinningBranchAndRevision", testPinningBranchAndRevision),
        ("testResolve", testResolve),
        ("testSeeAlso", testSeeAlso),
        ("testShowDependencies", testShowDependencies),
        ("testSymlinkedDependency", testSymlinkedDependency),
        ("testUpdate", testUpdate),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
        ("testWatchmanXcodeprojgen", testWatchmanXcodeprojgen),
    ]
}

extension RunToolTests {
    static let __allTests = [
        ("testFileDeprecation", testFileDeprecation),
        ("testMultipleExecutableAndExplicitExecutable", testMultipleExecutableAndExplicitExecutable),
        ("testMutualExclusiveFlags", testMutualExclusiveFlags),
        ("testSanitizeThread", testSanitizeThread),
        ("testSeeAlso", testSeeAlso),
        ("testUnkownProductAndArgumentPassing", testUnkownProductAndArgumentPassing),
        ("testUnreachableExecutable", testUnreachableExecutable),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
    ]
}

extension TestToolTests {
    static let __allTests = [
        ("testNumWorkersParallelRequeriment", testNumWorkersParallelRequeriment),
        ("testNumWorkersValue", testNumWorkersValue),
        ("testSanitizeThread", testSanitizeThread),
        ("testSeeAlso", testSeeAlso),
        ("testUsage", testUsage),
        ("testVersion", testVersion),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(BuildToolTests.__allTests),
        testCase(PackageToolTests.__allTests),
        testCase(RunToolTests.__allTests),
        testCase(TestToolTests.__allTests),
    ]
}
#endif
