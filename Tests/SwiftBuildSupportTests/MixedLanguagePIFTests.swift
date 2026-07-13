//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
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

@Suite
struct MixedLanguagePIFTests {
    private func makeProject(
        packageName: String,
        files: [String],
        targets: [TargetDescription],
        toolsVersion: ToolsVersion,
    ) async throws -> SwiftBuildSupport.PIF.Project {
        let packagePath = AbsolutePath("/\(packageName)")
        let fs = InMemoryFileSystem(emptyFiles: files)
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: packageName,
                    path: packagePath,
                    toolsVersion: toolsVersion,
                    targets: targets,
                ),
            ],
            observabilityScope: observability.topScope,
        )
        #expect(observability.diagnostics.isEmpty, "unexpected diagnostics loading \(packageName)")

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope,
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )
        return try pif.workspace.project(named: packageName)
    }

    private func mixedLanguageToolsVersion() throws -> ToolsVersion {
        try #require(ToolsVersion(string: "6.4.0", experimentalFeatures: [.experimentalMultiLang]))
    }

    @Test func mixedSwiftCLibrary() async throws {
        let project = try await makeProject(
            packageName: "MixedSwiftCLibrary",
            files: [
                "/MixedSwiftCLibrary/Sources/MixedSwiftCLibrary/Adder.swift",
                "/MixedSwiftCLibrary/Sources/MixedSwiftCLibrary/cadd.c",
                "/MixedSwiftCLibrary/Sources/MixedSwiftCLibrary/include/cadd.h",
            ],
            targets: [TargetDescription(name: "MixedSwiftCLibrary")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.target(named: "MixedSwiftCLibrary")
        let config = try target.buildConfig(named: .debug)

        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        #expect(config.settings[.SWIFT_OBJC_INTERFACE_HEADER_NAME] == "MixedSwiftCLibrary-Swift.h")
        #expect(config.settings[.DEFINES_MODULE] == "YES")

        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("module MixedSwiftCLibrary"))

        let headerSearchPaths = try #require(config.settings[.HEADER_SEARCH_PATHS])
        #expect(headerSearchPaths.contains("/MixedSwiftCLibrary/Sources/MixedSwiftCLibrary/include"))
        let ownSwiftFlags = try #require(config.settings[.OTHER_SWIFT_FLAGS])
        #expect(ownSwiftFlags.contains("-fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/MixedSwiftCLibrary.modulemap"))
    }

    @Test func mixedTargetWithCustomModuleMap() async throws {
        let customModuleMapPath = "/CustomModuleMapMixed/Sources/MixedCustom/include/module.modulemap"
        let project = try await makeProject(
            packageName: "CustomModuleMapMixed",
            files: [
                "/CustomModuleMapMixed/Sources/MixedCustom/Adder.swift",
                "/CustomModuleMapMixed/Sources/MixedCustom/cadd.c",
                "/CustomModuleMapMixed/Sources/MixedCustom/include/cadd.h",
                customModuleMapPath,
            ],
            targets: [TargetDescription(name: "MixedCustom")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.requireTarget(named: "MixedCustom")
        let config = try target.buildConfig(named: .debug)

        #expect(config.settings[.MODULEMAP_PATH] == customModuleMapPath)
        #expect(config.settings[.MODULEMAP_FILE_CONTENTS] == nil)
        #expect(config.settings[.SWIFT_EXTEND_MODULEMAP_FILE_CONTENTS] == nil)
        let ownSwiftFlags = try #require(config.settings[.OTHER_SWIFT_FLAGS])
        #expect(ownSwiftFlags.contains("-fmodule-map-file=\(customModuleMapPath)"))
        #expect(ownSwiftFlags.contains("-import-underlying-module"))

        let impartedCFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
        #expect(impartedCFlags.contains("-fmodule-map-file=\(customModuleMapPath)"))
        let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
        #expect(impartedSwiftFlags.contains("-fmodule-map-file=\(customModuleMapPath)"))
    }

    @Test func mixedTargetOwnHeaderSearchPathIncludesGeneratedDir() async throws {
        let project = try await makeProject(
            packageName: "MixedObjCUsesSwiftHeader",
            files: [
                "/MixedObjCUsesSwiftHeader/Sources/MixedLib/Greeter.swift",
                "/MixedObjCUsesSwiftHeader/Sources/MixedLib/Value.swift",
                "/MixedObjCUsesSwiftHeader/Sources/MixedLib/Bridge.m",
                "/MixedObjCUsesSwiftHeader/Sources/MixedLib/include/Bridge.h",
            ],
            targets: [TargetDescription(name: "MixedLib")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.requireTarget(named: "MixedLib")
        let config = try target.buildConfig(named: .debug)
        let headerSearchPaths = try #require(config.settings[.HEADER_SEARCH_PATHS])
        #expect(headerSearchPaths.contains("$(GENERATED_MODULEMAP_DIR)"))
    }

    @Test func headerOnlyObjCTargetIsMixed() async throws {
        let project = try await makeProject(
            packageName: "ObjCImplementationInSwift",
            files: [
                "/ObjCImplementationInSwift/Sources/MixedImpl/Widget.swift",
                "/ObjCImplementationInSwift/Sources/MixedImpl/include/Widget.h",
            ],
            targets: [TargetDescription(name: "MixedImpl")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.requireTarget(named: "MixedImpl")
        let config = try target.buildConfig(named: .debug)

        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        #expect(config.settings[.MODULEMAP_FILE_CONTENTS] != nil)
        let headerSearchPaths = try #require(config.settings[.HEADER_SEARCH_PATHS])
        #expect(headerSearchPaths.contains("$(GENERATED_MODULEMAP_DIR)"))
    }

    @Test func mixedSwiftCLibraryWithNoHeaders() async throws {
        let project = try await makeProject(
            packageName: "MixedSwiftCLibraryNoHeaders",
            files: [
                "/MixedSwiftCLibraryNoHeaders/Sources/MixedNoHeaders/Compute.swift",
                "/MixedSwiftCLibraryNoHeaders/Sources/MixedNoHeaders/helper.c",
            ],
            targets: [TargetDescription(name: "MixedNoHeaders")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.requireTarget(named: "MixedNoHeaders")
        let config = try target.buildConfig(named: .debug)

        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("header \"MixedNoHeaders-Swift.h\""))
        #expect(!moduleMap.contains("umbrella"))
        #expect(config.settings[.HEADER_SEARCH_PATHS] == ["$(inherited)", "$(GENERATED_MODULEMAP_DIR)"])
    }

    @Test func mixedSwiftCxxLibrary() async throws {
        let project = try await makeProject(
            packageName: "MixedSwiftCxxLibrary",
            files: [
                "/MixedSwiftCxxLibrary/Sources/MixedSwiftCxxLibrary/Multiplier.swift",
                "/MixedSwiftCxxLibrary/Sources/MixedSwiftCxxLibrary/mul.cpp",
                "/MixedSwiftCxxLibrary/Sources/MixedSwiftCxxLibrary/include/mul.h",
            ],
            targets: [TargetDescription(name: "MixedSwiftCxxLibrary")],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.target(named: "MixedSwiftCxxLibrary")
        let config = try target.buildConfig(named: .debug)

        #expect(config.settings[.DEFINES_MODULE] == "YES")
        #expect(config.settings[.MODULEMAP_FILE_CONTENTS] != nil)

        #expect(config.impartedBuildProperties.settings[.OTHER_LDFLAGS, .macOS] == ["$(inherited)", "-lc++"])
        #expect(config.impartedBuildProperties.settings[.OTHER_LDFLAGS, .linux] == ["$(inherited)", "-lstdc++"])
    }

    @Test func mixedSwiftCExecutable() async throws {
        let project = try await makeProject(
            packageName: "MixedSwiftCExecutable",
            files: [
                "/MixedSwiftCExecutable/Sources/MixedSwiftCExecutable/main.swift",
                "/MixedSwiftCExecutable/Sources/MixedSwiftCExecutable/helper.c",
                "/MixedSwiftCExecutable/Sources/MixedSwiftCExecutable/include/helper.h",
            ],
            targets: [TargetDescription(name: "MixedSwiftCExecutable", type: .executable)],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let target = try project.target(named: "MixedSwiftCExecutable")
        let config = try target.buildConfig(named: .debug)

        #expect(config.settings[.DEFINES_MODULE] == "YES")
        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("module MixedSwiftCExecutable"))
    }

    @Test func mixedLanguageClient() async throws {
        let project = try await makeProject(
            packageName: "MixedLanguageClient",
            files: [
                "/MixedLanguageClient/Sources/MixedCore/Adder.swift",
                "/MixedLanguageClient/Sources/MixedCore/cadd.c",
                "/MixedLanguageClient/Sources/MixedCore/include/cadd.h",
                "/MixedLanguageClient/Sources/Client/main.swift",
            ],
            targets: [
                TargetDescription(name: "MixedCore"),
                TargetDescription(name: "Client", dependencies: ["MixedCore"], type: .executable),
            ],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let core = try project.target(named: "MixedCore")
        let config = try core.buildConfig(named: .debug)

        let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
        #expect(impartedSwiftFlags.contains("-fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/MixedCore.modulemap"))
        let impartedCFlags = try #require(config.impartedBuildProperties.settings[.OTHER_CFLAGS])
        #expect(impartedCFlags.contains("-fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/MixedCore.modulemap"))
    }

    @Test func testTargetImportingMixedLibrary() async throws {
        let project = try await makeProject(
            packageName: "MixedLibraryTestTarget",
            files: [
                "/MixedLibraryTestTarget/Sources/MixedCore/Adder.swift",
                "/MixedLibraryTestTarget/Sources/MixedCore/cadd.c",
                "/MixedLibraryTestTarget/Sources/MixedCore/include/cadd.h",
                "/MixedLibraryTestTarget/Tests/MixedCoreTests/MixedCoreTests.swift",
            ],
            targets: [
                TargetDescription(name: "MixedCore"),
                TargetDescription(name: "MixedCoreTests", dependencies: ["MixedCore"], type: .test),
            ],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let core = try project.requireTarget(named: "MixedCore")
        let config = try core.buildConfig(named: .debug)
        let impartedSwiftFlags = try #require(config.impartedBuildProperties.settings[.OTHER_SWIFT_FLAGS])
        #expect(impartedSwiftFlags.contains("-fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/MixedCore.modulemap"))
    }

    @Test func testTargetImportingMixedExecutable() async throws {
        let project = try await makeProject(
            packageName: "MixedExecutableTestTarget",
            files: [
                "/MixedExecutableTestTarget/Sources/MixedTool/Tool.swift",
                "/MixedExecutableTestTarget/Sources/MixedTool/main.swift",
                "/MixedExecutableTestTarget/Sources/MixedTool/toolc.c",
                "/MixedExecutableTestTarget/Sources/MixedTool/include/toolc.h",
                "/MixedExecutableTestTarget/Tests/MixedToolTests/MixedToolTests.swift",
            ],
            targets: [
                TargetDescription(name: "MixedTool", type: .executable),
                TargetDescription(name: "MixedToolTests", dependencies: ["MixedTool"], type: .test),
            ],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let tool = try project.requireTarget(named: "MixedTool")
        let config = try tool.buildConfig(named: .debug)
        #expect(config.settings[.DEFINES_MODULE] == "YES")
        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("module MixedTool"))
    }

    @Test func mixedSourceTestTarget() async throws {
        let project = try await makeProject(
            packageName: "MixedSourceTestTarget",
            files: [
                "/MixedSourceTestTarget/Sources/Calculator/Calculator.swift",
                "/MixedSourceTestTarget/Tests/CalculatorTests/CalculatorTests.swift",
                "/MixedSourceTestTarget/Tests/CalculatorTests/test_helper.c",
                "/MixedSourceTestTarget/Tests/CalculatorTests/include/test_helper.h",
            ],
            targets: [
                TargetDescription(name: "Calculator"),
                TargetDescription(name: "CalculatorTests", dependencies: ["Calculator"], type: .test),
            ],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let testTarget = try project.requireTarget(named: "MixedSourceTestTargetPackageTests-product")
        let config = try testTarget.buildConfig(named: .debug)
        #expect(config.settings[.DEFINES_MODULE] == "YES")
        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("umbrella"))
    }

    @Test func mixedSourceMacro() async throws {
        let project = try await makeProject(
            packageName: "MixedSourceMacro",
            files: [
                "/MixedSourceMacro/Sources/MacroImpl/Plugin.swift",
                "/MixedSourceMacro/Sources/MacroImpl/helper.c",
                "/MixedSourceMacro/Sources/MacroImpl/include/helper.h",
                "/MixedSourceMacro/Sources/MacroDef/MacroDef.swift",
                "/MixedSourceMacro/Sources/MacroClient/main.swift",
            ],
            targets: [
                TargetDescription(name: "MacroImpl", type: .macro),
                TargetDescription(name: "MacroDef", dependencies: ["MacroImpl"]),
                TargetDescription(name: "MacroClient", dependencies: ["MacroDef"], type: .executable),
            ],
            toolsVersion: try mixedLanguageToolsVersion(),
        )
        let macro = try project.requireTarget(named: "MacroImpl")
        let config = try macro.buildConfig(named: .debug)

        #expect(config.settings[.SWIFT_INSTALL_OBJC_HEADER] == "YES")
        let moduleMap = try #require(config.settings[.MODULEMAP_FILE_CONTENTS])
        #expect(moduleMap.contains("module MacroImpl"))
        #expect(moduleMap.contains("umbrella"))
        let ownSwiftFlags = try #require(config.settings[.OTHER_SWIFT_FLAGS])
        #expect(ownSwiftFlags.contains("-fmodule-map-file=$(GENERATED_MODULEMAP_DIR)/MacroImpl.modulemap"))
    }
}

extension SwiftBuildSupport.PIF.Project {
    fileprivate func requireTarget(named name: String) throws -> ProjectModel.BaseTarget {
        if let target = underlying.targets.first(where: { $0.common.name == name }) {
            return target
        }
        throw StringError("no target named '\(name)'; available: \(underlying.targets.map(\.common.name))")
    }
}
