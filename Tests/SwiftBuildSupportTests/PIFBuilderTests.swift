//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Testing
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import SwiftBuild
import SwiftBuildSupport
import _InternalTestSupport
import Workspace

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph

// MARK: - Helpers

extension PIFBuilderParameters {
    static func constructDefaultParametersForTesting(
        temporaryDirectory: Basics.AbsolutePath,
        addLocalRpaths: Bool,
        shouldCreateDylibForDynamicProducts: Bool = false,
        pluginScriptRunner: PluginScriptRunner? = nil
    ) throws -> Self {
        try self.init(
            isPackageAccessModifierSupported: true,
            enableTestability: false,
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts,
            materializeStaticArchiveProductsForRootPackages: true,
            createDynamicVariantsForLibraryProducts: false,
            toolchainLibDir: temporaryDirectory.appending(component: "toolchain-lib-dir"),
            pkgConfigDirectories: [],
            supportedSwiftVersions: [.v4, .v4_2, .v5, .v6],
            pluginScriptRunner: pluginScriptRunner ?? DefaultPluginScriptRunner(
                fileSystem: localFileSystem,
                cacheDir: temporaryDirectory.appending(component: "plugin-cache-dir"),
                toolchain: try UserToolchain.default
            ),
            disableSandbox: false,
            pluginWorkingDirectory: temporaryDirectory.appending(component: "plugin-working-dir"),
            additionalFileRules: [],
            addLocalRPaths: addLocalRpaths
        )
    }
}

fileprivate func withGeneratedPIF(
    fromFixture fixtureName: String,
    addLocalRpaths: Bool = true,
    shouldCreateDylibForDynamicProducts: Bool = true,
    buildParameters: BuildParameters? = nil,
    do doIt: (SwiftBuildSupport.PIF.TopLevelObject, TestingObservability) async throws -> ()
) async throws {
    let buildParameters = if let buildParameters {
        buildParameters
    } else {
        mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
    }
    try await fixture(name: fixtureName) { fixturePath in
        let observabilitySystem: TestingObservability = ObservabilitySystem.makeForTesting(verbose: false)
        let toolchain = try UserToolchain.default
        var config = WorkspaceConfiguration.default
        config.shouldCreateMultipleTestProducts = true
        let workspace = try Workspace(
            fileSystem: localFileSystem,
            forRootPackage: fixturePath,
            configuration: config,
            customManifestLoader: ManifestLoader(toolchain: toolchain),
            delegate: MockWorkspaceDelegate()
        )
        let rootInput = PackageGraphRootInput(packages: [fixturePath], dependencies: [])
        let graph = try await workspace.loadPackageGraph(
            rootInput: rootInput,
            observabilityScope: observabilitySystem.topScope
        )
        let builder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: fixturePath,
                addLocalRpaths: addLocalRpaths,
                shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
            ),
            fileSystem: localFileSystem,
            observabilityScope: observabilitySystem.topScope
        )
        let pif = try await builder.constructPIF(
            buildParameters: buildParameters,
        )
        try await doIt(pif, observabilitySystem)
    }
}

extension SwiftBuildSupport.PIF.Workspace {
    fileprivate func project(named name: String) throws -> SwiftBuildSupport.PIF.Project {
        let matchingProjects = projects.filter {
            $0.underlying.name == name
        }
        if matchingProjects.isEmpty {
            throw StringError("No project named \(name) in PIF workspace")
        } else if matchingProjects.count > 1 {
            throw StringError("Multiple projects named \(name) in PIF workspace")
        } else {
            return matchingProjects[0]
        }
    }
}

extension SwiftBuildSupport.PIF.Project {
    fileprivate func target(id: String) throws -> ProjectModel.BaseTarget {
        let matchingTargets: [ProjectModel.BaseTarget] = underlying.targets.filter {
            return $0.common.id.value == String(id)
        }
        if matchingTargets.isEmpty {
            throw StringError("No target named \(id) in PIF project")
        } else if matchingTargets.count > 1 {
            throw StringError("Multiple target named \(id) in PIF project")
        } else {
            return matchingTargets[0]
        }
    }

    fileprivate func target(named name: String) throws -> ProjectModel.BaseTarget {
        let matchingTargets = underlying.targets.filter {
            $0.common.name == name
        }
        switch matchingTargets.count {
        case 0:
            throw StringError("No target named \(name) in PIF project, other targets: [\(underlying.targets.map(\.common.name).joined(separator: ", "))]")
        case 1:
            return matchingTargets[0]
        case 2:
            if let nonDynamicVariant = matchingTargets.filter({ !$0.id.value.hasSuffix("-dynamic") }).only {
                return nonDynamicVariant
            } else {
                fallthrough
            }
        default:
            throw StringError("Multiple targets named \(name) in PIF project")
        }
    }

    fileprivate func buildConfig(named name: BuildConfiguration) throws -> SwiftBuild.ProjectModel.BuildConfig {
        let matchingConfigs = underlying.buildConfigs.filter {
            $0.name == name.pifConfiguration
        }
        if matchingConfigs.isEmpty {
            throw StringError("No config named \(name) in PIF project")
        } else if matchingConfigs.count > 1 {
            throw StringError("Multiple configs named \(name) in PIF project")
        } else {
            return matchingConfigs[0]
        }
    }
}

extension SwiftBuild.ProjectModel.BaseTarget {
    fileprivate func buildConfig(named name: BuildConfiguration) throws -> SwiftBuild.ProjectModel.BuildConfig {
        let matchingConfigs = common.buildConfigs.filter {
            $0.name == name.pifConfiguration
        }
        if matchingConfigs.isEmpty {
            throw StringError("No config named \(name) in PIF target")
        } else if matchingConfigs.count > 1 {
            throw StringError("Multiple configs named \(name) in PIF target")
        } else {
            return matchingConfigs[0]
        }
    }
}

extension BuildConfiguration {
    var pifConfiguration: String {
        switch self {
            case .debug, .release: self.rawValue.capitalized
        }
    }
}

// MARK: - Tests

@Suite(
    .tags(
        .TestSize.medium,
        .FunctionalArea.PIF
    )
)
struct PIFBuilderTests {

    struct RootPackagesTestData {
        let id: String
        let rootPackages: [(name: String, path: Basics.AbsolutePath)]
        let expectedData: (pifPath: Basics.AbsolutePath, pifName: String, pifId: String)
    }
    @Test(
        arguments:[
            RootPackagesTestData(
                id: "Single root package, package path at root",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/fooPackage")),
                ],
                expectedData: (
                    pifPath: "/fooPackage",
                    pifName: "fooPackage",
                    pifId: "/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Single root package, package path nested ",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/d/fooPackage")),
                ],
                expectedData: (
                    pifPath: "/a/b/c/d/fooPackage",
                    pifName: "fooPackage",
                    pifId: "/a/b/c/d/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, unordered, no common parent directory",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/fooPackage")),
                    (name: "barPackage", path: AbsolutePath("/barPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath.root,
                    pifName: "barPackage,fooPackage",
                    pifId: "/barPackage,/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, ordered, no common parent directory",
                rootPackages: [
                    (name: "barPackage", path: AbsolutePath("/barPackage")),
                    (name: "fooPackage", path: AbsolutePath("/fooPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath.root,
                    pifName: "barPackage,fooPackage",
                    pifId: "/barPackage,/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, unordered, no common parent directory",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/fooPackage")),
                    (name: "barPackage", path: AbsolutePath("/barPackage")),
                    (name: "bazPackage", path: AbsolutePath("/bazPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath.root,
                    pifName: "barPackage,bazPackage,fooPackage",
                    pifId: "/barPackage,/bazPackage,/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Multiple root packages, ordered, no common parent directory",
                rootPackages: [
                    (name: "barPackage", path: AbsolutePath("/barPackage")),
                    (name: "bazPackage", path: AbsolutePath("/bazPackage")),
                    (name: "fooPackage", path: AbsolutePath("/fooPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath.root,
                    pifName: "barPackage,bazPackage,fooPackage",
                    pifId: "/barPackage,/bazPackage,/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, unordered, contains common directory, packages are sibling",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/fooPackage")),
                    (name: "barPackage", path: AbsolutePath("/a/b/c/barPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,fooPackage",
                    pifId: "/a/b/c/barPackage,/a/b/c/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, ordered, contains common directory, packages are sibling",
                rootPackages: [
                    (name: "barPackage", path: AbsolutePath("/a/b/c/barPackage")),
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/fooPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,fooPackage",
                    pifId: "/a/b/c/barPackage,/a/b/c/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, ybordered, contains common directory, packages are not siblings",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/pink/fuzz/fooPackage")),
                    (name: "barPackage", path: AbsolutePath("/a/b/c/absolute/zero/barPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,fooPackage",
                    pifId: "/a/b/c/absolute/zero/barPackage,/a/b/c/pink/fuzz/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Two root packages, ordered, contains common directory, packages are not siblings",
                rootPackages: [
                    (name: "barPackage", path: AbsolutePath("/a/b/c/absolute/zero/barPackage")),
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/pink/fuzz/fooPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,fooPackage",
                    pifId: "/a/b/c/absolute/zero/barPackage,/a/b/c/pink/fuzz/fooPackage",
                ),
            ),

            RootPackagesTestData(
                id: "Many root packages, unordered, contains common directory, packages are not siblings",
                rootPackages: [
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/pink/fuzz/fooPackage")),
                    (name: "barPackage", path: AbsolutePath("/a/b/c/absolute/zero/barPackage")),
                    (name: "bazPackage", path: AbsolutePath("/a/b/c/absolute/legend/bazPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,bazPackage,fooPackage",
                    pifId: "/a/b/c/absolute/zero/barPackage,/a/b/c/absolute/legend/bazPackage,/a/b/c/pink/fuzz/fooPackage",
                ),
            ),
            RootPackagesTestData(
                id: "Many root packages, ordered, contains common directory, packages are not siblings",
                rootPackages: [
                    (name: "barPackage", path: AbsolutePath("/a/b/c/absolute/zero/barPackage")),
                    (name: "bazPackage", path: AbsolutePath("/a/b/c/absolute/legend/bazPackage")),
                    (name: "fooPackage", path: AbsolutePath("/a/b/c/pink/fuzz/fooPackage")),
                ],
                expectedData: (
                    pifPath: Basics.AbsolutePath("/a/b/c"),
                    pifName: "barPackage,bazPackage,fooPackage",
                    pifId: "/a/b/c/absolute/zero/barPackage,/a/b/c/absolute/legend/bazPackage,/a/b/c/pink/fuzz/fooPackage",
                ),
            ),
        ],
    )
    func multipleRootPackages(
        testData: RootPackagesTestData,
    ) async throws {
        // Arrange
        try #require(testData.rootPackages.count >= 1, "Test configuration data error.  No root packages are specified.")

        let fs = InMemoryFileSystem()
        let observabilityScope = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: testData.rootPackages.map { rootPackage in
                Manifest.createRootManifest(
                    displayName: rootPackage.name,
                    path: rootPackage.path,
                    products: [],
                    targets: [],
                )
            },
            observabilityScope: observabilityScope.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: true,
            ),
            fileSystem: fs,
            observabilityScope: observabilityScope.topScope,
        )

        // Act
        let pif = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild),
        )

        // Assert
        #expect(
            pif.workspace.path == testData.expectedData.pifPath,
            "Actual path is not as expected",
        )
        #expect(
            pif.workspace.name == testData.expectedData.pifName,
            "Actual pif name is not as expected",
        )

    }

    @Test func platformExecutableModuleLibrarySearchPath() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/BasicExecutable") { pif, observabilitySystem in
            let releaseConfig = try pif.workspace
                .project(named: "BasicExecutable")
                .target(named: "Executable")
                .buildConfig(named: .release)

            for platform in ProjectModel.BuildSettings.Platform.allCases {
                let search_paths = releaseConfig.impartedBuildProperties.settings[.LIBRARY_SEARCH_PATHS, platform]
                switch platform {
                    case .macOS, .macCatalyst, .iOS, .watchOS, .tvOS, .xrOS, .driverKit, .freebsd, .android, .linux, .wasi, .openbsd, ._iOSDevice:
                         #expect(search_paths == nil, "for platform \(platform)")
                    case .windows:
                        #expect(search_paths == ["$(inherited)", "$(TARGET_BUILD_DIR)/ExecutableModules"], "for platform \(platform)")
                }
            }
        }
    }

    @Test func platformConditionBasics() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/UnknownPlatforms") { pif, observabilitySystem in
            // We should emit a warning to the PIF log about the unknown platform
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .warning && $0.message.contains("Ignoring settings assignments for unknown platform 'DoesNotExist'")
            }.count > 0)

            let releaseConfig = try pif.workspace
                .project(named: "UnknownPlatforms")
                .target(named: "UnknownPlatforms")
                .buildConfig(named: .release)

            // The platforms with conditional settings should have those propagated to the PIF.
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .linux] == ["$(inherited)", "BAR"])
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .macOS] == ["$(inherited)", "BAZ"])
            #expect(releaseConfig.settings[.SWIFT_ACTIVE_COMPILATION_CONDITIONS, .windows] == nil)
        }
    }

    @Test func platformCCLibrary() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/CCPackage") { pif, observabilitySystem in
            let releaseConfig = try pif.workspace
                .project(named: "CCPackage")
                .target(id: "PACKAGE-TARGET:CCTarget")
                .buildConfig(named: .release)

            for platform in ProjectModel.BuildSettings.Platform.allCases {
                let ld_flags = releaseConfig.impartedBuildProperties.settings[.OTHER_LDFLAGS, platform]
                switch platform {
                    case .macOS, .macCatalyst, .iOS, .watchOS, .tvOS, .xrOS, .driverKit, .freebsd:
                         #expect(ld_flags == ["-lc++", "$(inherited)"], "for platform \(platform)")
                    case .android, .linux, .wasi, .openbsd:
                        #expect(ld_flags == ["-lstdc++", "$(inherited)"], "for platform \(platform)")
                    case .windows, ._iOSDevice:
                        #expect(ld_flags == nil, "for platform \(platform)")
                }
            }
        }
    }

    @Test func packageWithInternal() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/PackageWithSDKSpecialization") { pif, observabilitySystem in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let releaseConfig = try pif.workspace
                .project(named: "PackageWithSDKSpecialization")
                .buildConfig(named: .release)

            #expect(releaseConfig.settings[.SPECIALIZATION_SDK_OPTIONS, .macOS] == ["foo"])
        }
    }

    @Test func pluginWithBinaryTargetDependency() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Plugins/BinaryTargetExePlugin") { pif, observabilitySystem in
            // Verify that PIF generation succeeds for a package with a plugin that depends on a binary target
            #expect(pif.workspace.projects.count > 0)

            let project = try pif.workspace.project(named: "MyBinaryTargetExePlugin")

            // Verify the plugin target exists
            let pluginTarget = try project.target(named: "MyPlugin")
            #expect(pluginTarget.common.name == "MyPlugin")

            // Verify the executable target that uses the plugin exists
            let executableTarget = try project.target(named: "MyPluginExe")
            #expect(executableTarget.common.name == "MyPluginExe")

            // Verify no errors were emitted during PIF generation
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            // Verify that the plugin target has a dependency (binary targets are handled differently in PIF)
            // The key test is that PIF generation succeeds without errors when a plugin depends on a binary target
            let binaryArtifactMessages = observabilitySystem.diagnostics.filter {
                $0.message.contains("found binary artifact")
            }
            #expect(binaryArtifactMessages.count > 0, "Expected to find binary artifact processing messages")
        }
    }

    @Test(.tags(
        .TestSize.medium,
        .FunctionalArea.PIF
    ))
    func parseAsLibrary() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/AtMainSupport") { pif, observabilitySystem in
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let project = try pif.workspace.project(named: "AtMainSupport")
            for targetName in ["SwiftExecSingleFile", "SwiftExecMultiFile"] {
                for config in BuildConfiguration.allCases {
                    let targetConfig = try project.target(named: targetName).buildConfig(named: config)
                    // These cases all use @main, so we should pass -parse-as-library.
                    #expect(targetConfig.settings[.SWIFT_LIBRARIES_ONLY] == "YES")
                    #expect(targetConfig.settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")
                }
            }
        }

        try await withGeneratedPIF(fromFixture: "Miscellaneous/EchoExecutable") { pif, observabilitySystem in
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let project = try pif.workspace.project(named: "EchoExecutable")
            for config in BuildConfiguration.allCases {
                // Executable target with no @main, do not pass -parse-as-library.
                let targetConfig = try project.target(named: "secho-product").buildConfig(named: config)
                #expect(targetConfig.settings[.SWIFT_LIBRARIES_ONLY] == "NO")
                #expect(targetConfig.settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "YES")
            }
        }

        try await withGeneratedPIF(fromFixture: "Miscellaneous/Plugins/PluginsAndSnippets") { pif, observabilitySystem in
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let project = try pif.workspace.project(named: "PluginsAndSnippets")
            for config in BuildConfiguration.allCases {
                do {
                    let targetConfig = try project.target(named: "ContainsMain-product").buildConfig(named: config)
                    #expect(targetConfig.settings[.SWIFT_LIBRARIES_ONLY] == "YES")
                    #expect(targetConfig.settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")
                }
                do {
                    let targetConfig = try project.target(named: "MySnippet-product").buildConfig(named: config)
                    #expect(targetConfig.settings[.SWIFT_LIBRARIES_ONLY] == "NO")
                    #expect(targetConfig.settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "YES")
                }
            }
        }
    }

    @Test(
        arguments: BuildConfiguration.allCases,
    )
    func dynamicLibraryProductExecutablePrefix(
        configuration: BuildConfiguration,
    ) async throws {
        try await withGeneratedPIF(
            fromFixture: "PIFBuilder/Library",
            shouldCreateDylibForDynamicProducts: true
        ) { pif, observabilitySystem in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let target = try pif.workspace
                .project(named: "Library")
                .target(named: "LibraryDynamic-product")

            guard case .target(let concreteTarget) = target else {
                Issue.record("Expected a regular target, got \(target)")
                return
            }
            #expect(concreteTarget.productType == .dynamicLibrary)
            let config = try target.buildConfig(named: configuration)
            #expect(config.settings[.EXECUTABLE_PREFIX] == "lib")
            #expect(config.settings[.EXECUTABLE_PREFIX, .windows] == "")
        }

        try await withGeneratedPIF(
            fromFixture: "PIFBuilder/Library",
            shouldCreateDylibForDynamicProducts: false
        ) { pif, observabilitySystem in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let target = try pif.workspace
                .project(named: "Library")
                .target(named: "LibraryDynamic-product")

            let config = try target.buildConfig(named: configuration)
            #expect(config.settings[.EXECUTABLE_PREFIX] == nil)
        }
    }

    @Test(
        arguments: BuildConfiguration.allCases,
    )
    func executablePrefixIsSetCorrectly(
        configuration: BuildConfiguration,
    ) async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/Library") { pif, observabilitySystem in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            struct ExpectedValue {
                let targetName: String
                let expectedValue: String?
                let expectedValueForWindows: String?
            }
            let targetsUnderTest = [
                ExpectedValue(
                    targetName: "LibraryDynamic-product",
                    expectedValue: "lib",
                    expectedValueForWindows: "",
                ),
                ExpectedValue(
                    targetName: "LibraryStatic-product",
                    expectedValue: "lib",
                    expectedValueForWindows: "",
                ),
                ExpectedValue(
                    targetName: "LibraryAuto-product",
                    expectedValue: "lib",
                    expectedValueForWindows: "",
                ),
            ]
            for targetUnderTest in targetsUnderTest {
                let projectConfig = try pif.workspace
                    .project(named: "Library")
                    .target(named: targetUnderTest.targetName)
                    .buildConfig(named: configuration)

                let actualValue = projectConfig.settings[.EXECUTABLE_PREFIX]
                let actualValueForWindows = projectConfig.settings[.EXECUTABLE_PREFIX, .windows]
                #expect(actualValue == targetUnderTest.expectedValue)
                #expect(actualValueForWindows == targetUnderTest.expectedValueForWindows)

            }
        }
    }


    @Test(arguments: BuildConfiguration.allCases)
    func conditionalLinkerSettings(configuration: BuildConfiguration) async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/ConditionalBuildSettings") { pif, observabilitySystem in
            let errors = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let targetConfig = try pif.workspace
                .project(named: "ConditionalBuildSettings")
                .target(id: "PACKAGE-TARGET:ConditionalBuildSettings")
                .buildConfig(named: configuration)

            let ldflags = targetConfig.settings[.OTHER_LDFLAGS]
            switch configuration {
            case .debug:
               let debugFlags = try #require(ldflags, "Debug config requires OTHER_LDFLAGS")
                #expect(
                    debugFlags.contains("-Xlinker") && debugFlags.contains("-interposable"),
                    "Debug config missing required flags: \(debugFlags)"
                )
            case .release:
                #expect(ldflags == nil, "Release config should not have debug flags, but got \(ldflags)")
            }
        }
    }

    @Test func impartedModuleMaps() async throws {
        try await withGeneratedPIF(fromFixture: "CFamilyTargets/ModuleMapGenerationCases") { pif, observabilitySystem in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "ModuleMapGenerationCases")
                    .target(named: "UmbrellaHeader")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.OTHER_CFLAGS] == ["-fmodule-map-file=\(RelativePath("$(GENERATED_MODULEMAP_DIR)").appending(component: "UmbrellaHeader.modulemap").pathString)", "$(inherited)"])
            }

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "ModuleMapGenerationCases")
                    .target(named: "UmbrellaDirectoryInclude")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.OTHER_CFLAGS] == ["-fmodule-map-file=\(RelativePath("$(GENERATED_MODULEMAP_DIR)").appending(component: "UmbrellaDirectoryInclude.modulemap").pathString)", "$(inherited)"])
            }

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "ModuleMapGenerationCases")
                    .target(named: "CustomModuleMap")
                    .buildConfig(named: .release)
                let arg = try #require(releaseConfig.impartedBuildProperties.settings[.OTHER_CFLAGS]?.first)
                #expect(arg.hasPrefix("-fmodule-map-file") && arg.hasSuffix(RelativePath("CustomModuleMap").appending(components: ["include", "module.modulemap"]).pathString))
            }
        }
    }

    @Test func disablingLocalRpaths() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Simple") { pif, observabilitySystem in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == ["$(RPATH_ORIGIN)", "$(inherited)"])
            }
        }

        try await withGeneratedPIF(fromFixture: "Miscellaneous/Simple", addLocalRpaths: false) { pif, observabilitySystem in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == nil)
            }
        }
    }

    @Test func warningSettingsInRemotePackage() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/RootLib/RootLib.swift",
            "/RemotePkg/Sources/swiftLib/swiftLib.swift",
            "/RemotePkg/Sources/cLib/cLib.c",
            "/RemotePkg/Sources/cLib/include/cLib.h",
            "/RemotePkg/Sources/cxxLib/cxxLib.cpp",
            "/RemotePkg/Sources/cxxLib/include/cxxLib.h",
            "/LocalPkg/Sources/localLib/localLib.swift",
        ])

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    toolsVersion: .v6_2,
                    dependencies: [
                        .remoteSourceControl(
                            url: "https://example.com/remote-pkg",
                            requirement: .upToNextMajor(from: "1.0.0")
                        ),
                        .fileSystem(path: "/LocalPkg"),
                    ],
                    products: [],
                    targets: [
                        TargetDescription(
                            name: "RootLib",
                            dependencies: [
                                .product(name: "RemoteLib", package: "remote-pkg"),
                                .product(name: "RemoteCLib", package: "remote-pkg"),
                                .product(name: "RemoteCXXLib", package: "remote-pkg"),
                                .product(name: "LocalLib", package: "LocalPkg"),
                            ]
                        ),
                    ]
                ),
                Manifest.createRemoteSourceControlManifest(
                    displayName: "remote-pkg",
                    url: "https://example.com/remote-pkg",
                    path: "/RemotePkg",
                    toolsVersion: .v6_2,
                    products: [
                        ProductDescription(name: "RemoteLib", type: .library(.automatic), targets: ["swiftLib"]),
                        ProductDescription(name: "RemoteCLib", type: .library(.automatic), targets: ["cLib"]),
                        ProductDescription(name: "RemoteCXXLib", type: .library(.automatic), targets: ["cxxLib"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "swiftLib",
                            settings: [
                                .init(tool: .swift, kind: .treatAllWarnings(.warning), condition: .init(config: "debug")),
                                .init(tool: .swift, kind: .treatAllWarnings(.error), condition: .init(config: "release")),
                                .init(tool: .swift, kind: .treatWarning("DeprecatedDeclaration", .error), condition: .init(config: "release")),
                            ]
                        ),
                        TargetDescription(
                            name: "cLib",
                            settings: [
                                .init(tool: .c, kind: .enableWarning("implicit-fallthrough"), condition: .init(config: "debug")),
                                .init(tool: .c, kind: .treatAllWarnings(.error), condition: .init(config: "release")),
                                .init(tool: .c, kind: .treatWarning("deprecated-declarations", .error), condition: .init(config: "release")),
                            ]
                        ),
                        TargetDescription(
                            name: "cxxLib",
                            settings: [
                                .init(tool: .cxx, kind: .enableWarning("implicit-fallthrough"), condition: .init(config: "debug")),
                                .init(tool: .cxx, kind: .treatAllWarnings(.error), condition: .init(config: "release")),
                                .init(tool: .cxx, kind: .treatWarning("deprecated-declarations", .error), condition: .init(config: "release")),
                            ]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "LocalPkg",
                    path: "/LocalPkg",
                    toolsVersion: .v6_2,
                    products: [
                        ProductDescription(name: "LocalLib", type: .library(.automatic), targets: ["localLib"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "localLib",
                            settings: [
                                .init(tool: .swift, kind: .treatAllWarnings(.error)),
                            ]
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root,
                addLocalRpaths: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let pif = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let remoteProject = try pif.workspace.project(named: "remote-pkg")
        for config in [BuildConfiguration.debug, .release] {
            #expect(try remoteProject.buildConfig(named: config).settings[.SUPPRESS_WARNINGS] == "YES")
        }

        let swiftLibTarget = try remoteProject.target(named: "swiftLib")
        let strippedSwiftFlags = ["-warnings-as-errors", "-no-warnings-as-errors", "-Wwarning", "-Werror", "DeprecatedDeclaration"]
        for config in [BuildConfiguration.debug, .release] {
            let swiftLibConfig = try swiftLibTarget.buildConfig(named: config)
            if let swiftFlags = swiftLibConfig.settings[.OTHER_SWIFT_FLAGS] {
                for flag in strippedSwiftFlags {
                    #expect(!swiftFlags.contains(flag))
                }
            }
        }

        for clangLibTargetName in ["cLib", "cxxLib"] {
            let cLibTarget = try remoteProject.target(named: clangLibTargetName)
            for config in [BuildConfiguration.debug, .release] {
                let cLibConfig = try cLibTarget.buildConfig(named: config)
                if let cFlags = cLibConfig.settings[.OTHER_CFLAGS] {
                    #expect(cFlags.filter { $0.count > 2 && $0.hasPrefix("-W") }.isEmpty)
                }
                if let cPlusPlusFlags = cLibConfig.settings[.OTHER_CPLUSPLUSFLAGS] {
                    #expect(cPlusPlusFlags.filter { $0.count > 2 && $0.hasPrefix("-W") }.isEmpty)
                }
            }
        }

        let localProject = try pif.workspace.project(named: "LocalPkg")

        for config in [BuildConfiguration.debug, .release] {
            #expect(try localProject.buildConfig(named: config).settings[.SUPPRESS_WARNINGS] == nil)
        }

        let localLibTarget = try localProject.target(named: "localLib")
        for config in [BuildConfiguration.debug, .release] {
            #expect(try localLibTarget.buildConfig(named: config).settings[.OTHER_SWIFT_FLAGS]?.contains("-warnings-as-errors") == true)
        }
    }

    @Suite(
        .tags(
            .FunctionalArea.IndexMode
        )
    )
    struct IndexModeSettingTests {

        @Test(
            arguments: [BuildParameters.IndexStoreMode.auto], [BuildConfiguration.debug],
            // arguments: BuildParameters.IndexStoreMode.allCases, BuildConfiguration.allCases,
        )
         func indexModeSettingSetTo(
            indexStoreSettingUT: BuildParameters.IndexStoreMode,
            configuration: BuildConfiguration,
         ) async throws {
            try await withGeneratedPIF(
                fromFixture: "PIFBuilder/Simple",
                buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild, indexStoreMode: indexStoreSettingUT),
            ) { pif, observabilitySystem in
                // #expect(false, "fail purposefully...")
                #expect(observabilitySystem.diagnostics.filter {
                    $0.severity == .error
                }.isEmpty)

                let targetConfig = try pif.workspace
                    .project(named: "Simple")
                    // .target(named: "Simple")
                    .buildConfig(named: configuration)
                switch indexStoreSettingUT {
                    case .on, .off:
                        #expect(targetConfig.settings[.SWIFT_INDEX_STORE_ENABLE] == nil)
                    case .auto:
                        let expectedSwiftIndexStoreEnableValue: String? = switch configuration {
                            case .debug: "YES"
                            case .release: nil
                        }
                        #expect(targetConfig.settings[.SWIFT_INDEX_STORE_ENABLE] == expectedSwiftIndexStoreEnableValue)
                }

                let testTargetConfig = try pif.workspace
                    .project(named: "Simple")
                    .target(named: "SimpleTests-product")
                    .buildConfig(named: configuration)
                switch indexStoreSettingUT {
                    case .on, .off:
                        #expect(testTargetConfig.settings[.SWIFT_INDEX_STORE_ENABLE] == nil)
                    case .auto:
                        #expect(testTargetConfig.settings[.SWIFT_INDEX_STORE_ENABLE] == "YES")
                }
            }
        }
    }

    @Test func swiftCompileForStaticLinkingInDynamicLibraries() async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/ModuleA/ModuleA.swift",
            "/Root/Sources/ModuleB/ModuleB.swift",
            "/Root/Sources/ModuleC/ModuleC.swift",
        ])

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    toolsVersion: .v6_0,
                    products: [
                        ProductDescription(name: "DynamicLib", type: .library(.dynamic), targets: ["ModuleA", "ModuleB"]),
                        ProductDescription(name: "StaticLib", type: .library(.static), targets: ["ModuleC"]),
                    ],
                    targets: [
                        TargetDescription(name: "ModuleA"),
                        TargetDescription(name: "ModuleB"),
                        TargetDescription(name: "ModuleC"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: true
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let pif = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let project = try pif.workspace.project(named: "Root")

        // Modules that are direct dependencies of dynamic library products should have
        // SWIFT_COMPILE_FOR_STATIC_LINKING = "NO" on Windows
        for moduleName in ["ModuleA", "ModuleB"] {
            let moduleTarget = try project.target(named: moduleName)
            let config = try moduleTarget.buildConfig(named: .release)

            // Check that the setting is "NO" on Windows
            #expect(
                config.settings[.SWIFT_COMPILE_FOR_STATIC_LINKING, .windows] == "NO",
                "Module \(moduleName) in dynamic library should have SWIFT_COMPILE_FOR_STATIC_LINKING=NO on Windows"
            )

            // Check that the setting is not set on other platforms
            for platform in SwiftBuild.ProjectModel.BuildSettings.Platform.allCases where platform != .windows {
                #expect(
                    config.settings[.SWIFT_COMPILE_FOR_STATIC_LINKING, platform] == nil,
                    "Module \(moduleName) should not have SWIFT_COMPILE_FOR_STATIC_LINKING on platform \(platform)"
                )
            }
        }

        // Modules that are NOT in dynamic library products should not have this setting
        let moduleC = try project.target(named: "ModuleC")
        let moduleCConfig = try moduleC.buildConfig(named: .release)

        for platform in ProjectModel.BuildSettings.Platform.allCases {
            let setting = moduleCConfig.settings[.SWIFT_COMPILE_FOR_STATIC_LINKING, platform]
            #expect(
                setting == nil,
                "Module ModuleC (not in dynamic library) should not have SWIFT_COMPILE_FOR_STATIC_LINKING on platform \(platform)"
            )
        }
    }
}
