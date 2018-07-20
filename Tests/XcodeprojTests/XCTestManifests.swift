#if !os(macOS)
import XCTest

extension FunctionalTests {
    static let __allTests = [
        ("testModuleNamesWithNonC99Names", testModuleNamesWithNonC99Names),
        ("testSingleModuleLibrary", testSingleModuleLibrary),
        ("testSwiftExecWithCDep", testSwiftExecWithCDep),
        ("testSystemModule", testSystemModule),
        ("testXcodeProjWithPkgConfig", testXcodeProjWithPkgConfig),
    ]
}

extension GenerateXcodeprojTests {
    static let __allTests = [
        ("testBuildXcodeprojPath", testBuildXcodeprojPath),
        ("testGenerateXcodeprojWithDotFiles", testGenerateXcodeprojWithDotFiles),
        ("testGenerateXcodeprojWithFilesIgnoredByGit", testGenerateXcodeprojWithFilesIgnoredByGit),
        ("testGenerateXcodeprojWithInvalidModuleNames", testGenerateXcodeprojWithInvalidModuleNames),
        ("testGenerateXcodeprojWithNonSourceFilesInSourceDirectories", testGenerateXcodeprojWithNonSourceFilesInSourceDirectories),
        ("testGenerateXcodeprojWithoutGitRepo", testGenerateXcodeprojWithoutGitRepo),
        ("testGenerateXcodeprojWithRootFiles", testGenerateXcodeprojWithRootFiles),
        ("testXcconfigOverrideValidatesPath", testXcconfigOverrideValidatesPath),
        ("testXcodebuildCanParseIt", testXcodebuildCanParseIt),
    ]
}

extension PackageGraphTests {
    static let __allTests = [
        ("testAggregateTarget", testAggregateTarget),
        ("testBasics", testBasics),
        ("testModuleLinkage", testModuleLinkage),
        ("testModulemap", testModulemap),
        ("testSchemes", testSchemes),
        ("testSwiftVersion", testSwiftVersion),
    ]
}

extension PropertyListTests {
    static let __allTests = [
        ("testBasics", testBasics),
    ]
}

extension XcodeProjectModelSerializationTests {
    static let __allTests = [
        ("testBasicProjectSerialization", testBasicProjectSerialization),
        ("testBuildFileSettingsSerialization", testBuildFileSettingsSerialization),
        ("testBuildSettingsSerialization", testBuildSettingsSerialization),
    ]
}

extension XcodeProjectModelTests {
    static let __allTests = [
        ("testBasicProjectCreation", testBasicProjectCreation),
        ("testBuildPhases", testBuildPhases),
        ("testBuildSettings", testBuildSettings),
        ("testProductReferences", testProductReferences),
        ("testTargetCreation", testTargetCreation),
        ("testTargetDependencies", testTargetDependencies),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(FunctionalTests.__allTests),
        testCase(GenerateXcodeprojTests.__allTests),
        testCase(PackageGraphTests.__allTests),
        testCase(PropertyListTests.__allTests),
        testCase(XcodeProjectModelSerializationTests.__allTests),
        testCase(XcodeProjectModelTests.__allTests),
    ]
}
#endif
