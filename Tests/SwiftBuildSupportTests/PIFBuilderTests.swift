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
import Foundation
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
        addLocalRpaths: PackagePIFBuilder.AddLocalRpaths,
        shouldCreateDylibForDynamicProducts: Bool = false,
        pluginScriptRunner: PluginScriptRunner? = nil,
        hostBuildProductsPath: Basics.AbsolutePath? = nil
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
            addLocalRpaths: addLocalRpaths,
            hostBuildProductsPath: hostBuildProductsPath ?? temporaryDirectory.appending(component: "host-build-products"),
            shouldPreserveSymlinks: false
        )
    }
}

fileprivate func withGeneratedPIF(
    fromFixture fixtureName: String,
    withPackage packageName: String? = nil,
    addLocalRpaths: PackagePIFBuilder.AddLocalRpaths = .always,
    shouldCreateDylibForDynamicProducts: Bool = true,
    buildParameters: BuildParameters? = nil,
    hostBuildProductsPath: AbsolutePath? = nil,
    do doIt: (SwiftBuildSupport.PIF.TopLevelObject, TestingObservability, AbsolutePath) async throws -> ()
) async throws {
    let buildParameters = if let buildParameters {
        buildParameters
    } else {
        mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
    }
    try await fixture(name: fixtureName) { tmpFixturePath in
        let fixturePath = if let packageName {
            tmpFixturePath.appending(packageName)
        } else {
            tmpFixturePath
        }
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
                shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts,
                hostBuildProductsPath: hostBuildProductsPath
            ),
            fileSystem: localFileSystem,
            observabilityScope: observabilitySystem.topScope
        )
        let (pif, _) = try await builder.constructPIF(
            buildParameters: buildParameters
        )
        try await doIt(pif, observabilitySystem, fixturePath)
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
            throw StringError("No target named \(name) in PIF project")
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
                addLocalRpaths: .always,
            ),
            fileSystem: fs,
            observabilityScope: observabilityScope.topScope,
        )

        // Act
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
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
        try await withGeneratedPIF(fromFixture: "PIFBuilder/BasicExecutable") { pif, observabilitySystem, fixturePath in
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

    struct ModuleAliasTestData {
        let fixtureName: String
        let packageName: String
        let projectName: String
        let verify: [Verify]

        struct Verify {
            let targetName: String
            let expectedAliases: [String]
        }
    }
    @Test(
        arguments: [
            ModuleAliasTestData(
                fixtureName: "ModuleAliasing/Executable",
                packageName: "App",
                projectName: "App",
                verify: [
                    ModuleAliasTestData.Verify(
                        targetName: "App-product",
                        expectedAliases: ["Utils=AppUtils"],
                    ),
                ],
            ),
        ]
    )
    func moduleAliasesPropagateToExecutableProduct(
        data: ModuleAliasTestData,
    ) async throws {
        try await withGeneratedPIF(
            fromFixture: data.fixtureName,
            withPackage: data.packageName,
        ) { pif, observabilitySystem, fixturePath in
            let project = try pif.workspace.project(named: data.projectName)
            for v in data.verify {
                let productConfig = try project
                    .target(named: v.targetName)
                    .buildConfig(named: .debug)

                #expect(
                    productConfig.settings[.SWIFT_MODULE_ALIASES] == v.expectedAliases,
                    "Project name \(data.projectName) and target name \(v.targetName) does not have expected module aliases",
                )
            }
        }
    }

    struct ModuleAliasTargetTestData {
        let fixtureName: String
        let packageName: String
        /// Expected `SWIFT_MODULE_ALIASES` entries (formatted as `"OriginalName=AliasName"`)
        /// that must appear across the union of every `PACKAGE-TARGET:` target in the generated PIF.
        let expectedAliasEntries: Set<String>
    }
    @Test(
        arguments: [
            ModuleAliasTargetTestData(
                fixtureName: "ModuleAliasing/DirectDeps1",
                packageName: "AppPkg",
                expectedAliasEntries: ["Utils=GameUtils"],
            ),
            ModuleAliasTargetTestData(
                fixtureName: "ModuleAliasing/DirectDeps2",
                packageName: "AppPkg",
                expectedAliasEntries: ["Utils=AUtils", "Utils=BUtils"],
            ),
            ModuleAliasTargetTestData(
                fixtureName: "ModuleAliasing/Executable",
                packageName: "App",
                expectedAliasEntries: ["Utils=AppUtils"],
            ),
            ModuleAliasTargetTestData(
                fixtureName: "ModuleAliasing/NestedDeps1",
                packageName: "AppPkg",
                expectedAliasEntries: [
                    "FooUtils=AFooUtils",
                    "FooUtils=XFooUtils",
                    "Utils=CarUtils",
                    "Utils=XUtils",
                ],
            ),
            ModuleAliasTargetTestData(
                fixtureName: "ModuleAliasing/NestedDeps2",
                packageName: "AppPkg",
                expectedAliasEntries: [
                    "Utils=BUtils",
                    "Utils=CUtils",
                    "Utils=XUtils",
                ],
            ),
        ]
    )
    func moduleAliasesPropagateToPackageTargets(
        data: ModuleAliasTargetTestData,
    ) async throws {
        try await withGeneratedPIF(
            fromFixture: data.fixtureName,
            withPackage: data.packageName,
        ) { pif, _, _ in
            var seenAliasEntries: Set<String> = []
            for project in pif.workspace.projects {
                for target in project.underlying.targets {
                    guard target.common.id.value.hasPrefix("PACKAGE-TARGET:") else { continue }
                    for config in target.common.buildConfigs {
                        guard let aliases = config.settings[.SWIFT_MODULE_ALIASES] else { continue }
                        for entry in aliases {
                            seenAliasEntries.insert(entry)
                        }
                    }
                }
            }
            #expect(
                seenAliasEntries.isSuperset(of: data.expectedAliasEntries),
                "\(data.fixtureName): PACKAGE-TARGET SWIFT_MODULE_ALIASES missing expected entries; expected superset of \(data.expectedAliasEntries), got \(seenAliasEntries)",
            )
        }
    }

    @Test
    func emitUnhandledFilesOnlyForRootPackages() async throws {
        try await withGeneratedPIF(
            fromFixture: "PIFBuilder/UnhandledFiled",
            withPackage: "App",
        ) { pif, observabilitySystem, fixturePath in


            let actualUnhandledFilesWarnings =  observabilitySystem.warnings.filter { $0.message.contains("which are unhandled;")}
            let expected: [Basics.Diagnostic] =  [
                Basics.Diagnostic.unhandledFiles([
                    fixturePath.appending(components: ["Sources", "App", "Foo.txt"]),
                    fixturePath.appending(components: ["Sources", "App", "README.md"]),
                ])
            ]

            #expect(
                observabilitySystem.hasErrorDiagnostics == false,
                "Unexepcted errors occurred >> \(observabilitySystem.errors)"
            )
            #expect(
                actualUnhandledFilesWarnings.count == expected.count,
                "Actual number of diagnostics is not as expected... actual: \(actualUnhandledFilesWarnings)",
            )
        }
    }

    @Test
    func emitUnhandledFilesAsErrorWhenWarningsAsErrors() async throws {
        try await withGeneratedPIF(
            fromFixture: "PIFBuilder/UnhandledFiled",
            withPackage: "App",
            buildParameters: mockBuildParameters(
                destination: .host,
                flags: BuildFlags(swiftCompilerFlags: [BuildFlag(value: "-warnings-as-errors", source: nil)]),
                buildSystemKind: .swiftbuild,
            ),
        ) { pif, observabilitySystem, fixturePath in

            let expected: [Basics.Diagnostic] = [
                Basics.Diagnostic.unhandledFiles([
                    fixturePath.appending(components: ["Sources", "App", "Foo.txt"]),
                    fixturePath.appending(components: ["Sources", "App", "README.md"]),
                ])
            ]

            // With `-warnings-as-errors`, the unhandled files diagnostic should be
            // emitted as an error rather than a warning.
            let actualUnhandledFilesErrors = observabilitySystem.errors.filter {
                $0.message.contains("which are unhandled;")
            }
            #expect(
                actualUnhandledFilesErrors.map(\.message) == expected.map(\.message),
                "Expected the unhandled files diagnostic to be emitted as an error... actual: \(observabilitySystem.errors)",
            )

            // It should no longer be emitted as a warning.
            let actualUnhandledFilesWarnings = observabilitySystem.warnings.filter {
                $0.message.contains("which are unhandled;")
            }
            #expect(
                actualUnhandledFilesWarnings.isEmpty,
                "Did not expect the unhandled files diagnostic to be emitted as a warning... actual: \(actualUnhandledFilesWarnings)",
            )
        }
    }

    @Test func platformConditionBasics() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/UnknownPlatforms") { pif, observabilitySystem, fixturePath in
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
        try await withGeneratedPIF(fromFixture: "PIFBuilder/CCPackage") { pif, observabilitySystem, fixturePath in
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
        try await withGeneratedPIF(fromFixture: "PIFBuilder/PackageWithSDKSpecialization") { pif, observabilitySystem, fixturePath in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let releaseConfig = try pif.workspace
                .project(named: "PackageWithSDKSpecialization")
                .buildConfig(named: .release)

            #expect(releaseConfig.settings[.SPECIALIZATION_SDK_OPTIONS, .macOS] == ["foo"])
        }
    }

    @Test func pluginWithBinaryTargetDependency() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Plugins/BinaryTargetExePlugin") { pif, observabilitySystem, fixturePath in
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

    @Test func buildToolPluginCommandLineUsesHostBuildPath() async throws {
        let hostBuildPath = AbsolutePath("/path/to/host/build")
        let destBuildPath = AbsolutePath("/path/to/dest/build")
        let destBuildParams = mockBuildParameters(
            destination: .host,
            buildPath: destBuildPath,
            buildSystemKind: .swiftbuild
        )

        try await withGeneratedPIF(
            fromFixture: "Miscellaneous/Plugins/MySourceGenPlugin",
            buildParameters: destBuildParams,
            hostBuildProductsPath: hostBuildPath
        ) { pif, observabilitySystem, fixturePath in
            let project = try pif.workspace.project(named: "MySourceGenPlugin")
            let target = try project.target(named: "MyLocalTool-product")
            for task in target.common.customTasks {
                let commandLine = task.commandLine
                #expect(commandLine.contains { $0.contains(hostBuildPath.pathString) })
                #expect(!commandLine.contains { $0.contains(destBuildPath.pathString) })
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
        ) { pif, observabilitySystem, fixturePath in
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
        ) { pif, observabilitySystem, fixturePath in
            let errors: [Diagnostic] = observabilitySystem.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

            let target = try pif.workspace
                .project(named: "Library")
                .target(named: "LibraryDynamic-product")

            let config = try target.buildConfig(named: configuration)
            #expect(config.settings[.EXECUTABLE_PREFIX] == nil)
        }
    }

    @Test(arguments: [true, false])
    func dynamicVariantProductName(createDylibForDynamicProducts: Bool) async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(
            emptyFiles: [
                "/MyPkg/Sources/MyLib/MyLib.swift",
            ]
        )

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "MyPkg",
                    path: "/MyPkg",
                    toolsVersion: .v6_2,
                    products: [
                        .init(name: "MyLibDynamic", type: .library(.dynamic), targets: ["MyLib"]),
                    ],
                    targets: [
                        .init(name: "MyLib"),
                    ]
                )
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root,
                addLocalRpaths: .always,
                shouldCreateDylibForDynamicProducts: createDylibForDynamicProducts
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )
        #expect(!observability.hasErrorDiagnostics)

        let project = try pif.workspace.project(named: "MyPkg")

        let moduleVariant = try #require(
            project.underlying.targets.first {
                $0.common.name == "MyLib" && $0.common.id.value.hasSuffix("-dynamic")
            }
        )
        guard case .target(let moduleTarget) = moduleVariant else {
            Issue.record("Expected a regular target for the dynamic module variant, got \(moduleVariant)")
            return
        }

        let productVariant = try project.target(named: "MyLibDynamic-product")
        guard case .target(let productTarget) = productVariant else {
            Issue.record("Expected a regular target for the dynamic product, got \(productVariant)")
            return
        }

        if createDylibForDynamicProducts {
            #expect(moduleTarget.productType == .dynamicLibrary)
            #expect(moduleTarget.productName == "$(EXECUTABLE_NAME)")

            #expect(productTarget.productType == .dynamicLibrary)
            #expect(productTarget.productName == "$(EXECUTABLE_NAME)")
        } else {
            #expect(moduleTarget.productType == .framework)
            #expect(moduleTarget.productName == "$(WRAPPER_NAME)")

            #expect(productTarget.productType == .framework)
            #expect(productTarget.productName == "$(WRAPPER_NAME)")
        }
    }

    @Test(
        arguments: BuildConfiguration.allCases,
    )
    func executablePrefixIsSetCorrectly(
        configuration: BuildConfiguration,
    ) async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/Library") { pif, observabilitySystem, fixturePath in
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
        try await withGeneratedPIF(fromFixture: "PIFBuilder/ConditionalBuildSettings") { pif, observabilitySystem, fixturePath in
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

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/10225", relationship: .verifies),
        arguments: BuildConfiguration.allCases
    )
    func testRunnerInheritsUnitTestLinkerFlags(configuration: BuildConfiguration) async throws {
        let observability = ObservabilitySystem.makeForTesting()

        let fs = InMemoryFileSystem(emptyFiles: [
            "/Root/Sources/Lib/Lib.swift",
            "/Root/Tests/LibTests/LibTests.swift",
        ])

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                .createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    toolsVersion: .v6_2,
                    targets: [
                        TargetDescription(name: "Lib"),
                        TargetDescription(
                            name: "LibTests",
                            dependencies: ["Lib"],
                            type: .test,
                            settings: [
                                .init(tool: .linker, kind: .unsafeFlags(["-L", "/Vendor"])),
                                .init(tool: .linker, kind: .linkedLibrary("helper")),
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
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )
        #expect(!observability.hasErrorDiagnostics)

        let project = try pif.workspace.project(named: "Root")

        let runnerTarget = try #require(
            project.underlying.targets.first {
                guard case .target(let target) = $0 else { return false }
                return target.productType == .swiftpmTestRunner
            }
        )

        let ldFlags = try #require(try runnerTarget.buildConfig(named: configuration).settings[.OTHER_LDFLAGS])
        #expect(ldFlags.contains("-lhelper"))
        #expect(ldFlags.contains("-L") && ldFlags.contains("/Vendor"))
    }

    @Test func impartedModuleMaps() async throws {
        try await withGeneratedPIF(fromFixture: "CFamilyTargets/ModuleMapGenerationCases") { pif, observabilitySystem, fixturePath in
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

    @Test func moduleMapPathAndContents() async throws {
        try await withGeneratedPIF(fromFixture: "PIFBuilder/Library") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let releaseConfig = try pif.workspace
                .project(named: "Library")
                .target(named: "Library")
                .buildConfig(named: .release)

            let expectedPath = try RelativePath(validating: "$(GENERATED_MODULEMAP_DIR)/Library.modulemap").pathString
            #expect(releaseConfig.settings[.MODULEMAP_PATH] == expectedPath)
            #expect(releaseConfig.settings[.MODULEMAP_FILE_CONTENTS] == """
            module Library {
            header "Library-Swift.h"
            export *
            }
            """)
        }

        try await withGeneratedPIF(fromFixture: "CFamilyTargets/ModuleMapGenerationCases") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let project = try pif.workspace.project(named: "ModuleMapGenerationCases")

            do {
                let releaseConfig = try project
                    .target(named: "NoIncludeDir")
                    .buildConfig(named: .release)

                #expect(releaseConfig.settings[.MODULEMAP_PATH] == nil)
                #expect(releaseConfig.settings[.MODULEMAP_FILE_CONTENTS] == nil)
            }

            do {
                let releaseConfig = try project
                    .target(named: "CustomModuleMap")
                    .buildConfig(named: .release)

                let path = try #require(releaseConfig.settings[.MODULEMAP_PATH])
                #expect(path.hasSuffix(RelativePath("CustomModuleMap")
                    .appending(components: ["include", "module.modulemap"]).pathString))
                #expect(!path.contains("$(GENERATED_MODULEMAP_DIR)"))
                #expect(releaseConfig.settings[.MODULEMAP_FILE_CONTENTS] == nil)
            }

            do {
                let releaseConfig = try project
                    .target(named: "UmbrellaHeader")
                    .buildConfig(named: .release)

                let expectedPath = try RelativePath(
                    validating: "$(GENERATED_MODULEMAP_DIR)/UmbrellaHeader.modulemap"
                ).pathString
                #expect(releaseConfig.settings[.MODULEMAP_PATH] == expectedPath)

                let contents = try #require(releaseConfig.settings[.MODULEMAP_FILE_CONTENTS])
                #expect(contents.hasPrefix("module UmbrellaHeader {"))
                #expect(contents.contains("umbrella header \""))
                #expect(contents.contains(RelativePath("UmbrellaHeader")
                    .appending(components: ["include", "UmbrellaHeader", "UmbrellaHeader.h"]).escapedPathString))
                #expect(contents.contains("export *"))
            }

            do {
                let releaseConfig = try project
                    .target(named: "UmbrellaDirectoryInclude")
                    .buildConfig(named: .release)

                let expectedPath = try RelativePath(
                    validating: "$(GENERATED_MODULEMAP_DIR)/UmbrellaDirectoryInclude.modulemap"
                ).pathString
                #expect(releaseConfig.settings[.MODULEMAP_PATH] == expectedPath)

                let contents = try #require(releaseConfig.settings[.MODULEMAP_FILE_CONTENTS])
                #expect(contents.hasPrefix("module UmbrellaDirectoryInclude {"))
                #expect(contents.contains("umbrella \""))
                #expect(!contents.contains("umbrella header"))
                #expect(contents.contains(RelativePath("UmbrellaDirectoryInclude")
                    .appending(component: "include").escapedPathString))
                #expect(contents.contains("export *"))
            }
        }
    }

    @Test func disablingLocalRpaths() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Simple") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let debugConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .debug)

                #expect(debugConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == ["$(RPATH_ORIGIN)", "$(BUILT_PRODUCTS_DIR)/PackageFrameworks", "$(inherited)"])
            }

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == ["$(RPATH_ORIGIN)", "$(inherited)"])
            }
        }

        try await withGeneratedPIF(fromFixture: "Miscellaneous/Simple", addLocalRpaths: .never) { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let debugConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .debug)

                #expect(debugConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == nil)
            }

            do {
                let releaseConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .release)

                #expect(releaseConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == nil)
            }
        }
    }

    @Test func debugOnlyLocalRpaths() async throws {
        try await withGeneratedPIF(
            fromFixture: "Miscellaneous/Simple",
            addLocalRpaths: .debugOnly
        ) { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter {
                $0.severity == .error
            }.isEmpty)

            do {
                let debugConfig = try pif.workspace
                    .project(named: "Foo")
                    .target(named: "Foo")
                    .buildConfig(named: .debug)

                #expect(debugConfig.impartedBuildProperties.settings[.LD_RUNPATH_SEARCH_PATHS] == ["$(RPATH_ORIGIN)", "$(BUILT_PRODUCTS_DIR)/PackageFrameworks", "$(inherited)"])
            }

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
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let (pif, _) = try await pifBuilder.constructPIF(
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
            ) { pif, observabilitySystem, fixturePath in
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
                        #expect(targetConfig.settings[.INDEX_ENABLE_DATA_STORE] == nil)
                    case .auto:
                        let expectedSwiftIndexStoreEnableValue: String? = switch configuration {
                            case .debug: "YES"
                            case .release: nil
                        }
                        #expect(targetConfig.settings[.INDEX_ENABLE_DATA_STORE] == expectedSwiftIndexStoreEnableValue)
                }

                let testTargetConfig = try pif.workspace
                    .project(named: "Simple")
                    .target(named: "SimpleTests-product")
                    .buildConfig(named: configuration)
                switch indexStoreSettingUT {
                    case .on, .off:
                        #expect(testTargetConfig.settings[.INDEX_ENABLE_DATA_STORE] == nil)
                    case .auto:
                        #expect(testTargetConfig.settings[.INDEX_ENABLE_DATA_STORE] == "YES")
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
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let (pif, _) = try await pifBuilder.constructPIF(
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

    @Test func macroPackageSupportedPlatforms() async throws {
        try await withGeneratedPIF(fromFixture: "Macros/MinimalMacroPackage") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)
            let project = try pif.workspace.project(named: "MinimalMacroPackage")
            let projectPlatforms = try project.buildConfig(named: .debug).settings[.SUPPORTED_PLATFORMS]
            #expect(projectPlatforms == ["$(AVAILABLE_PLATFORMS)"])
            let targets = project.underlying.targets
            for target in targets {
                let id = target.common.id.value
                let config = try target.buildConfig(named: .debug)
                let platforms = config.settings[.SUPPORTED_PLATFORMS]
                if id == "PACKAGE-TARGET:MacroImpl" {
                    #expect(platforms == ["$(HOST_PLATFORM)"], "target \(id) did not have the expected supported platform setting")
                } else {
                    #expect(platforms == nil, "target \(id) has supported platforms set, unexpectedly")
                }
            }
        }
    }

    @Test func testTargetWithTransitiveMacroImplementationDependency() async throws {
        try await withGeneratedPIF(fromFixture: "Macros/MinimalMacroPackage") { pif, observabilitySystem, _ in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let project = try pif.workspace.project(named: "MinimalMacroPackage")

            let testProduct = try project.target(named: "MinimalMacroPackageTests-product")
            guard case .target(let testTarget) = testProduct else {
                Issue.record("Expected MinimalMacroPackageTests-product to be a regular target")
                return
            }
            #expect(testTarget.productType == .unitTest)

            let depIDs = testTarget.common.dependencies.map(\.targetId.value)

            // The macro implementation is a transitive dependency of the tests. The PIF should represent this
            // dependency, but it should not be a linkage dependency, and the macro helpers also should not be
            // linked.
            #expect(depIDs.contains("PACKAGE-TARGET:MacroImpl"))
            #expect(!depIDs.contains { $0.hasPrefix("PACKAGE-TARGET:MacroImpl-") && $0.hasSuffix("-testable") })
            #expect(!depIDs.contains("PACKAGE-TARGET:MacroImplHelpers"))
        }
    }

    @Test func testTargetWithDirectMacroImplementationDependency() async throws {
        try await withGeneratedPIF(fromFixture: "Macros/MacroWithDirectTestDependency") { pif, observabilitySystem, _ in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let project = try pif.workspace.project(named: "MacroWithDirectTestDependency")

            let testProduct = try project.target(named: "MacroImplTests-product")
            guard case .target(let testTarget) = testProduct else {
                Issue.record("Expected MacroImplTests-product to be a regular target")
                return
            }
            #expect(testTarget.productType == .unitTest)

            let depIDs = testTarget.common.dependencies.map(\.targetId.value)

            // The macro implementation is a direct dependency of the test target. Ensure the testable variant and
            // the helpers are linkage dependencies.
            #expect(depIDs.contains { $0.hasPrefix("PACKAGE-TARGET:MacroImpl-") && $0.hasSuffix("-testable") })
            #expect(depIDs.contains("PACKAGE-TARGET:MacroImplHelpers"))
        }
    }

    @Test func mixedSourceTarget() async throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Pkg/Sources/lib/file1.swift",
                "/Pkg/Sources/lib/file2.c"
        )
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: "/Pkg",
                    toolsVersion: try #require(ToolsVersion(string: "6.4.0", experimentalFeatures: [.experimentalMultiLang])),
                    targets: [
                        TargetDescription(name: "lib"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )
        #expect(observability.diagnostics.isEmpty)

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let project = try pif.workspace.project(named: "Pkg")
        let lib = try project.target(named: "lib")

        // Ensure both sources are included
        let sourcesPhase: ProjectModel.SourcesBuildPhase = try #require(lib.common.buildPhases.compactMap({
            guard case let .sources(sourcesBuildPhase) = $0 else {
                return nil
            }
            return sourcesBuildPhase
        }).only)

        let sources: [Basics.AbsolutePath] = sourcesPhase.files.compactMap({
            guard case .reference(id: let refId) = $0.ref else {
                return nil
            }
            return try? project.underlying.mainGroup.findSource(ref: refId)
        }).sorted()
        let expected: [Basics.AbsolutePath] = [
            "/Pkg/Sources/lib/file1.swift",
            "/Pkg/Sources/lib/file2.c",
        ]
        #expect(sources == expected)
     }

    @Test func testTargetDependsOnTestTarget() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/TestTargetDependsOnTestTarget") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let project = try pif.workspace.project(named: "TestTargetDependsOnTestTarget")

            // TestUtils is depended upon by other test targets, so it must be built as a static
            // library — not a test bundle — so dependents can link against it.
            let testUtils = try project.target(named: "TestUtils")
            guard case .target(let testUtilsTarget) = testUtils else {
                Issue.record("Expected TestUtils to be a regular target")
                return
            }
            #expect(testUtilsTarget.productType == .commonStaticArchive)

            // There must be no test bundle product for TestUtils.
            #expect(throws: (any Error).self) {
                try project.target(named: "TestUtils-product")
            }

            // Both consuming test targets are still unit test bundles.
            let fooTests = try project.target(named: "FooTests-product")
            guard case .target(let fooTestsTarget) = fooTests else {
                Issue.record("Expected FooTests-product to be a regular target")
                return
            }
            #expect(fooTestsTarget.productType == .unitTest)
            #expect(fooTestsTarget.common.dependencies.map(\.targetId).contains("PACKAGE-TARGET:TestUtils"))

            let barTests = try project.target(named: "BarTests-product")
            guard case .target(let barTestsTarget) = barTests else {
                Issue.record("Expected BarTests-product to be a regular target")
                return
            }
            #expect(barTestsTarget.productType == .unitTest)
            #expect(barTestsTarget.common.dependencies.map(\.targetId).contains("PACKAGE-TARGET:TestUtils"))
        }
    }

    @Test func noHeaderMaps() async throws {
        try await withGeneratedPIF(fromFixture: "Miscellaneous/Simple") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)
            let project = try pif.workspace.project(named: "Foo")
            for configName in [BuildConfiguration.debug, .release] {
                #expect(
                    try project.buildConfig(named: configName).settings[.USE_HEADERMAP] == "NO",
                    "config: \(configName)"
                )
            }
        }
    }

    @Test func symbolGraphExtractorBuildSettings() async throws {
        try await withGeneratedPIF(fromFixture: "CFamilyTargets/ModuleMapGenerationCases") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            // configureSourceModuleBuildSettings is called for every source module via the same
            // delegate path, so verifying on representative C targets is sufficient coverage.
            for targetName in ["UmbrellaHeader", "FlatInclude"] {
                let config = try pif.workspace
                    .project(named: "ModuleMapGenerationCases")
                    .target(named: targetName)
                    .buildConfig(named: .release)

                let expectedDir = "$(TARGET_BUILD_DIR)/$(CURRENT_ARCH)/\(targetName).symbolgraphs"
                #expect(config.settings[.SYMBOL_GRAPH_EXTRACTOR_OUTPUT_DIR] == expectedDir, "target: \(targetName)")
                #expect(config.settings[.TAPI_EXTRACT_API_OUTPUT_DIR] == expectedDir, "target: \(targetName)")
                #expect(config.settings[.DOCC_EXTRACT_PROJECT_HEADERS_DOCUMENTATION] == "YES", "target: \(targetName)")
            }
        }
    }

    @Test func cFamilyHeadersAddedToHeadersBuildPhase() async throws {
        try await withGeneratedPIF(fromFixture: "CFamilyTargets/ModuleMapGenerationCases") { pif, observabilitySystem, fixturePath in
            #expect(observabilitySystem.diagnostics.filter { $0.severity == .error }.isEmpty)

            let project = try pif.workspace.project(named: "ModuleMapGenerationCases")

            // UmbrellaHeader has include/UmbrellaHeader/UmbrellaHeader.h — expect a headers build phase
            do {
                let umbrellaTarget = try project.target(named: "UmbrellaHeader")
                let umbrellaHeadersPhase: ProjectModel.HeadersBuildPhase = try #require(
                    umbrellaTarget.common.buildPhases.compactMap({
                        guard case let .headers(phase) = $0 else { return nil }
                        return phase
                    }).only,
                    "Expected exactly one headers build phase for UmbrellaHeader"
                )

                let umbrellaHeaderPaths: [AbsolutePath] = umbrellaHeadersPhase.files.compactMap {
                    guard case .reference(id: let refId) = $0.ref else { return nil }
                    return try? project.underlying.mainGroup.findSource(ref: refId)
                }.sorted()
                #expect(umbrellaHeaderPaths.contains { $0.basename == "UmbrellaHeader.h" })
                // nil headerVisibility means "project" visibility — what we set for symbol graph extraction
                #expect(umbrellaHeadersPhase.files.allSatisfy { $0.headerVisibility == nil })
            }

            // FlatInclude has include/FlatIncludeHeader.h — expect a headers build phase
            do {
                let flatIncludeTarget = try project.target(named: "FlatInclude")
                let flatIncludeHeadersPhase: ProjectModel.HeadersBuildPhase = try #require(
                    flatIncludeTarget.common.buildPhases.compactMap({
                        guard case let .headers(phase) = $0 else { return nil }
                        return phase
                    }).only,
                    "Expected exactly one headers build phase for FlatInclude"
                )

                let flatIncludeHeaderPaths: [AbsolutePath] = flatIncludeHeadersPhase.files.compactMap {
                    guard case .reference(id: let refId) = $0.ref else { return nil }
                    return try? project.underlying.mainGroup.findSource(ref: refId)
                }.sorted()
                #expect(flatIncludeHeaderPaths.contains { $0.basename == "FlatIncludeHeader.h" })
                #expect(flatIncludeHeadersPhase.files.allSatisfy { $0.headerVisibility == nil })
            }

            // NoIncludeDir has no header files — should have no headers build phase
            do {
                let noIncludeDirTarget = try project.target(named: "NoIncludeDir")
                let noHeadersPhases = noIncludeDirTarget.common.buildPhases.filter {
                    guard case .headers = $0 else { return false }
                    return true
                }
                #expect(noHeadersPhases.isEmpty)
            }
        }
    }

    /// Regression test: a build tool plugin and its executable tool live in the same dependency
    /// package, but the executable product has a different name than its underlying target.
    ///
    /// Before the fix, SwiftPM auto-promotes an implicit product named after the target alongside
    /// the explicit product. Both matched `productRepresentingDependencyOfBuildPlugin`, causing
    /// `only` to return nil and no PIF dependency being added to the plugin target.
    @Test func buildToolPluginWithExplicitProductNameSamePackage() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem(emptyFiles: [
            "/PluginPkg/Plugins/MyPlugin/plugin.swift",
            "/PluginPkg/Sources/PluginTool/main.swift",
            "/Root/Sources/RootLib/RootLib.swift",
        ])

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    toolsVersion: .v5_9,
                    dependencies: [.fileSystem(path: "/PluginPkg")],
                    products: [],
                    targets: [
                        TargetDescription(
                            name: "RootLib",
                            pluginUsages: [.plugin(name: "MyPlugin", package: "PluginPkg")]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "PluginPkg",
                    path: "/PluginPkg",
                    toolsVersion: .v5_9,
                    products: [
                        // Explicit product name differs from the underlying target name — this
                        // is the exact case that triggered the bug.
                        ProductDescription(name: "plugin-tool", type: .executable, targets: ["PluginTool"]),
                        ProductDescription(name: "MyPlugin", type: .plugin, targets: ["MyPlugin"]),
                    ],
                    targets: [
                        TargetDescription(name: "PluginTool", type: .executable),
                        TargetDescription(
                            name: "MyPlugin",
                            dependencies: ["PluginTool"],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always,
                pluginScriptRunner: NoOpPluginScriptRunner()
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let errors = observability.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

        let pluginPkgProject = try pif.workspace.project(named: "PluginPkg")
        // The explicit product generates a PIF target named "<productName>-product".
        let pluginToolProductTarget = try pluginPkgProject.target(named: "plugin-tool-product")
        let pluginTarget = try pluginPkgProject.target(named: "MyPlugin")

        #expect(
            pluginTarget.common.dependencies.contains { $0.targetId == pluginToolProductTarget.common.id },
            "Expected MyPlugin to depend on plugin-tool-product (the explicit product). Actual dependencies: \(pluginTarget.common.dependencies.map(\.targetId.value))"
        )
    }

    /// Tests the cross-package case: the build tool plugin lives in one package and its
    /// executable tool lives in a separate package. The plugin declares the dependency via
    /// `.product(name:package:)`, which routes through a different code path than the
    /// same-package case.
    @Test func buildToolPluginWithExecutableProductCrossPackage() async throws {
        let observability = ObservabilitySystem.makeForTesting()
        let fs = InMemoryFileSystem(emptyFiles: [
            "/ToolPkg/Sources/MyTool/main.swift",
            "/PluginPkg/Plugins/MyPlugin/plugin.swift",
            "/Root/Sources/RootLib/RootLib.swift",
        ])

        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    toolsVersion: .v5_9,
                    dependencies: [
                        .fileSystem(path: "/ToolPkg"),
                        .fileSystem(path: "/PluginPkg"),
                    ],
                    products: [],
                    targets: [
                        TargetDescription(
                            name: "RootLib",
                            pluginUsages: [.plugin(name: "MyPlugin", package: "PluginPkg")]
                        ),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "ToolPkg",
                    path: "/ToolPkg",
                    toolsVersion: .v5_9,
                    products: [
                        // Explicit product name differs from the underlying target name.
                        ProductDescription(name: "my-tool", type: .executable, targets: ["MyTool"]),
                    ],
                    targets: [
                        TargetDescription(name: "MyTool", type: .executable),
                    ]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "PluginPkg",
                    path: "/PluginPkg",
                    toolsVersion: .v5_9,
                    dependencies: [.fileSystem(path: "/ToolPkg")],
                    products: [
                        ProductDescription(name: "MyPlugin", type: .plugin, targets: ["MyPlugin"]),
                    ],
                    targets: [
                        TargetDescription(
                            name: "MyPlugin",
                            dependencies: [.product(name: "my-tool", package: "ToolPkg")],
                            type: .plugin,
                            pluginCapability: .buildTool
                        ),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always,
                pluginScriptRunner: NoOpPluginScriptRunner()
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )

        let errors = observability.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected no errors during PIF generation, but got: \(errors)")

        let toolPkgProject = try pif.workspace.project(named: "ToolPkg")
        let pluginPkgProject = try pif.workspace.project(named: "PluginPkg")

        let myToolProductTarget = try toolPkgProject.target(named: "my-tool-product")
        let pluginTarget = try pluginPkgProject.target(named: "MyPlugin")

        #expect(
            pluginTarget.common.dependencies.contains { $0.targetId == myToolProductTarget.common.id },
            "Expected MyPlugin to depend on my-tool-product from ToolPkg. Actual dependencies: \(pluginTarget.common.dependencies.map(\.targetId.value))"
        )
    }
}

/// A no-op plugin script runner for use in PIF builder tests that need a plugin in the graph
/// but don't care about the plugin's build commands.
private struct NoOpPluginScriptRunner: PluginScriptRunner {
    func compilePluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: any PluginScriptCompilerDelegate,
        completion: @escaping (Result<PluginCompilationResult, any Error>) -> Void
    ) {
        callbackQueue.sync { completion(.failure(StringError("unimplemented"))) }
    }

    func buildCommandLine(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope?
    ) -> (commandLine: [String], execName: String, execFilePath: AbsolutePath, diagFilePath: AbsolutePath) {
        fatalError("Not implemented")
    }

    func runPluginScript(
        sourceFiles: [AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        workers: UInt32,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: any PluginScriptCompilerDelegate & PluginScriptRunnerDelegate
    ) async throws -> Int32 {
        return 0
    }

    var hostTriple: Triple {
        get throws { try UserToolchain.default.targetTriple }
    }
}

extension ProjectModel.Group {
    func findSource(ref: GUID) throws -> Basics.AbsolutePath? {
        for child in subitems {
            switch child {
            case .file(let file):
                if file.id == ref {
                    if let file = try? Basics.AbsolutePath(validating: file.path) {
                        return file
                    }
                    guard self.pathBase == .absolute else {
                        return nil
                    }
                    let groupPath = try Basics.AbsolutePath(validating: self.path)
                    return groupPath.appending(file.path)
                }
            case .group(let group):
                if let file = try group.findSource(ref: ref) {
                    return file
                }
            }
        }
        return nil
    }
}

// MARK: - Promoted Executable Product Tests

/// A `PackagePIFBuilder.BuildDelegate` that lets a test control `customProductType(forExecutable:)`
/// while returning the same defaults as the production delegate for everything else.
private final class PromotingBuildDelegate: PackagePIFBuilder.BuildDelegate {
    let package: ResolvedPackage
    let promotedProductType: ProjectModel.Target.ProductType?

    init(package: ResolvedPackage, promotedProductType: ProjectModel.Target.ProductType?) {
        self.package = package
        self.promotedProductType = promotedProductType
    }

    var isRootPackage: Bool { self.package.manifest.packageKind.isRoot }
    var isRemote: Bool { self.package.manifest.packageKind.isRemote }
    var hostsOnlyPackages: Bool { false }
    var isUserManaged: Bool { true }
    var isBranchOrRevisionBased: Bool { false }
    var isPluginExecutionSandboxingDisabled: Bool { false }

    func customProductType(forExecutable product: PackageModel.Product) -> ProjectModel.Target.ProductType? {
        self.promotedProductType
    }

    func deviceFamilyIDs() -> Set<Int> { [] }
    func shouldPackagesBuildForARM64e(platform: PackageModel.Platform) -> Bool { false }
    func configureProjectBuildSettings(_ buildSettings: inout ProjectModel.BuildSettings) {}
    func configureSourceModuleBuildSettings(sourceModule: ResolvedModule, settings: inout ProjectModel.BuildSettings) {}
    func customInstallPath(product: PackageModel.Product) -> String? { nil }
    func customProductName(forFramework product: PackageModel.Product) -> String? { nil }
    func customBundleIdentifierPrefix(forFramework product: PackageModel.Product) -> String? { nil }
    func customLibraryType(product: PackageModel.Product) -> PackageModel.ProductType.LibraryType? { nil }
    func customSDKOptions(forPlatform: PackageModel.Platform) -> [String] { [] }

    func addCustomTargets(pifProject: inout ProjectModel.Project) throws -> [PackagePIFBuilder.ModuleOrProduct] { [] }

    func shouldSuppressProductDependency(
        product: PackageModel.Product,
        buildSettings: inout ProjectModel.BuildSettings
    ) -> Bool { false }

    func shouldSetInstallPathForDynamicLib(productName: String) -> Bool { false }

    func configureLibraryProduct(
        product: PackageModel.Product,
        project: inout ProjectModel.Project,
        target: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        additionalFiles: WritableKeyPath<ProjectModel.Group, ProjectModel.Group>
    ) {}

    func suggestAlignedPlatformVersionGiveniOSVersion(
        platform: PackageModel.Platform,
        iOSVersion: PackageModel.PlatformVersion
    ) -> String? { nil }

    func validateMacroFingerprint(for macroModule: ResolvedModule) -> Bool { true }
}

/// Builds the PIF project for a package that has an executable product (module `AppModule`) and a unit
/// test target that depends on it, promoting the executable to `promotedProductType` via the delegate.
private func buildAppProject(
    promotedProductType: ProjectModel.Target.ProductType?
) async throws -> ProjectModel.Project {
    let observability = ObservabilitySystem.makeForTesting()

    let fs = InMemoryFileSystem(emptyFiles: [
        "/App/Sources/AppModule/main.swift",
        "/App/Tests/AppTests/AppTests.swift",
    ])

    let graph = try loadModulesGraph(
        fileSystem: fs,
        manifests: [
            Manifest.createRootManifest(
                displayName: "App",
                path: "/App",
                toolsVersion: .v5_9,
                products: [
                    ProductDescription(name: "App", type: .executable, targets: ["AppModule"]),
                ],
                targets: [
                    TargetDescription(name: "AppModule", type: .executable),
                    TargetDescription(name: "AppTests", dependencies: ["AppModule"], type: .test),
                ]
            ),
        ],
        observabilityScope: observability.topScope
    )

    let rootPackage = try #require(graph.rootPackages.first)

    let delegate = PromotingBuildDelegate(package: rootPackage, promotedProductType: promotedProductType)
    let builder = PackagePIFBuilder(
        modulesGraph: graph,
        resolvedPackage: rootPackage,
        packageManifest: rootPackage.manifest,
        delegate: delegate,
        buildToolPluginResultsByTargetName: [String: [PackagePIFBuilder.BuildToolPluginInvocationResult]](),
        packageDisplayVersion: rootPackage.manifest.displayName,
        pkgConfigDirectories: [],
        fileSystem: fs,
        observabilityScope: observability.topScope
    )
    _ = try builder.build()

    #expect(!observability.hasErrorDiagnostics, "Unexpected errors: \(observability.errors)")

    // Keep the delegate alive for the duration of the build (`PackagePIFBuilder` holds it `unowned`).
    withExtendedLifetime(delegate) {}

    return builder.pifProject
}

extension ProjectModel.Project {
    /// The main-module product target for a product, e.g. `App-product`.
    fileprivate func productTarget(named name: String) throws -> ProjectModel.Target {
        try self.onlyTarget {
            guard case .target(let t) = $0 else { return false }
            return t.common.name == name
        }
    }

    /// The testable variant target for an executable module, e.g. `PACKAGE-TARGET:AppModule-<hash>-testable`.
    fileprivate func testableVariantTarget(forModule moduleName: String) throws -> ProjectModel.Target {
        try self.onlyTarget {
            guard case .target(let t) = $0 else { return false }
            return t.id.value.hasPrefix("PACKAGE-TARGET:\(moduleName)") && t.id.value.hasSuffix("-testable")
        }
    }

    private func onlyTarget(where predicate: (ProjectModel.BaseTarget) -> Bool) throws -> ProjectModel.Target {
        let matches = self.targets.filter(predicate)
        guard let match = matches.only, case .target(let target) = match else {
            throw StringError("Expected exactly one matching target, found \(matches.count)")
        }
        return target
    }
}

extension ProjectModel.Target {
    fileprivate func debugSettings() throws -> ProjectModel.BuildSettings {
        guard let config = self.common.buildConfigs.first(where: { $0.name == "Debug" }) else {
            throw StringError("No Debug build config in target \(self.id.value)")
        }
        return config.settings
    }
}

@Suite(
    .tags(
        .TestSize.medium,
        .FunctionalArea.PIF
    )
)
struct PromotedExecutableProductPIFTests {
    @Test
    func promotedAppProductInstallsItsOwnSwiftModule() async throws {
        // When an executable product is promoted to a non-executable PIF product (e.g. a mac catalyst app),
        // the product target must install its own Swift module so downstream tooling (Previews)
        // can find `<module>.swiftmodule`. A genuine executable product suppresses module installation to avoid
        // conflicting with its testable variant.

        // Promoted to an application: the product installs its module (setting is left unset).
        let promotedProject = try await buildAppProject(promotedProductType: .application)
        let promotedProductSettings = try promotedProject.productTarget(named: "App-product").debugSettings()
        #expect(
            promotedProductSettings[.SWIFT_INSTALL_MODULE] != "NO",
            "A promoted (non-executable) product must install its own Swift module"
        )

        // A genuine executable product does not install its module — the testable variant does.
        let executableProject = try await buildAppProject(promotedProductType: nil)
        let executableProductSettings = try executableProject.productTarget(named: "App-product").debugSettings()
        #expect(
            executableProductSettings[.SWIFT_INSTALL_MODULE] == "NO",
            "A genuine executable product must not install its Swift module"
        )
    }

    @Test
    func promotedAppWithUnitTestsInstallsModuleExactlyOnce() async throws {
        // When a promoted app also has unit tests, the executable gains a testable variant that would install a
        // module of the same name to the same location as the product target — producing a "Multiple commands
        // produce <module>.swiftmodule" build error. The testable variant's module installation must be suppressed
        // so exactly one target installs the module.
        let project = try await buildAppProject(promotedProductType: .application)

        let productSettings = try project.productTarget(named: "App-product").debugSettings()
        let testableVariantSettings = try project.testableVariantTarget(forModule: "AppModule").debugSettings()

        // The product installs the module; the testable variant is suppressed. Exactly one installer, no collision.
        #expect(
            productSettings[.SWIFT_INSTALL_MODULE] != "NO",
            "The promoted product target must remain the sole module installer"
        )
        #expect(
            testableVariantSettings[.SWIFT_INSTALL_MODULE] == "NO",
            "The testable variant must suppress module installation when the product installs its own"
        )
    }

    @Test
    func genuineExecutableTestableVariantStillInstallsModule() async throws {
        // A genuine executable's testable variant keeps installing its module. Multiple executable products can
        // share one executable target, so the per-target testable variant remains the installer. This guards against
        // over-suppressing the fix above.
        let project = try await buildAppProject(promotedProductType: nil)
        let testableVariantSettings = try project.testableVariantTarget(forModule: "AppModule").debugSettings()
        #expect(
            testableVariantSettings[.SWIFT_INSTALL_MODULE] != "NO",
            "A genuine executable's testable variant must still install its Swift module"
        )
    }
}
