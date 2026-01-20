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

import _InternalTestSupport
import Basics
import Testing
import PackageGraph
import PackageLoading
import PackageModel
import SPMBuildCore
import Workspace
import SwiftBuild
@testable import SwiftBuildSupport

// MARK: - Tests

/// Unit tests at the lower `PackagePIFBuilder` level for the `Fixtures/PIFBuilder/ExecutableAndLibrary` package.
///
/// We expect the following PIF targets (with the given names and PIF GUIDs):
///
/// * FooExecutable  PACKAGE-PRODUCT:pifbuilder_executableandlibrary_FooExecutable.FooExecutable
/// * FooExecutable  PACKAGE-TARGET:FooExecutable--2309126765E3E0CD-testable
/// * FooLibrary         PACKAGE-PRODUCT:pifbuilder_executableandlibrary_FooLibrary.FooLibrary
/// * FooLibrary         PACKAGE-PRODUCT:pifbuilder_executableandlibrary_FooLibrary.FooLibrary-71F03C173B935203-dynamic
/// * FooLibrary         PACKAGE-TARGET:FooLibrary
/// * FooLibrary         PACKAGE-TARGET:FooLibrary-71F03C173B935203-dynamic
@Suite(.serialized)
struct ExecutableAndLibraryPIFBuilderTests {

    @Test func packageProductsAndTargets() async throws {
        try await withPackagePIFBuilders(fromFixture: "PIFBuilder/ExecutableAndLibrary") { packagesAndBuilders, observabilitySystem in
            let packageAndPifBuilder: (package: ResolvedPackage, pifBuilder: PackagePIFBuilder) = try #require(packagesAndBuilders.only)

            let package: ResolvedPackage = packageAndPifBuilder.package
            #expect(package.manifest.displayName == "ExecutableAndLibrary")
            #expect(package.products.count == 2)
            #expect(package.modules.count == 2)

            let executableProduct = try #require(package.products.only { $0.name == "FooExecutable"})
            let executableModule = try #require(package.modules.only { $0.name == "FooExecutable"})

            #expect(executableProduct.modules == [executableModule])
            #expect(executableModule.sources.paths.count == 1)

            let libraryProduct = try #require(package.products.only { $0.name == "FooLibrary"})
            let libraryModule = try #require(package.modules.only { $0.name == "FooLibrary"})

            #expect(libraryProduct.modules == [libraryModule])
            #expect(libraryModule.sources.paths.count == 1)

            let pifBuilder: PackagePIFBuilder = packageAndPifBuilder.pifBuilder
            let modulesOrProducts: [PackagePIFBuilder.ModuleOrProduct] = try pifBuilder.build()

            #expect(modulesOrProducts.count == 6)

//            print(">>> =======================")
//            print(">>> modulesOrProducts", modulesOrProducts.count)
//            for moduleOrProduct in modulesOrProducts {
//                print(
//                    ">>> moduleOrProduct:",
//                    moduleOrProduct.name,
//                    moduleOrProduct.pifTarget!.common.id
//                    , "linked:", moduleOrProduct.linkedPackageBinaries.count
//                )
//            }
//            print(">>> =======================")
        }
    }

    /// Module → .target(name: "FooLibrary").
    @Test func libraryModule() async throws {
        try await withPackagePIFBuilders(fromFixture: "PIFBuilder/ExecutableAndLibrary") { packagesAndBuilders, observabilitySystem in
            let packagePifBuilder: PackagePIFBuilder = try #require(packagesAndBuilders.only?.pifBuilder)
            let modulesOrProducts: [PackagePIFBuilder.ModuleOrProduct] = try packagePifBuilder.build()

            let libraryModulePIFTarget = try #require(modulesOrProducts.only {
                try $0.name == "FooLibrary" &&
                $0.underlyingPIFTarget.productType == .commonObject &&
                !$0.underlyingPIFTarget.isVariant(.dynamic)
            })

            #expect(libraryModulePIFTarget.type == .commonObject)
            #expect(libraryModulePIFTarget.indexableFileURLs.count == 1)
            #expect(libraryModulePIFTarget.linkedPackageBinaries.count == 0)
            try #expect(libraryModulePIFTarget.underlyingPIFTarget.id.value == "PACKAGE-TARGET:FooLibrary")
            try #expect(libraryModulePIFTarget.underlyingPIFTarget.name == "FooLibrary")
            try #expect(libraryModulePIFTarget.underlyingPIFTarget.productType == .commonObject)
            try #expect(libraryModulePIFTarget.underlyingPIFTarget.sourceFiles.count == 1)
            try #expect(libraryModulePIFTarget.underlyingPIFTarget.linkedTargets.count == 0)
        }
    }

    /*

   /// Product → .library(name: "FooLibrary")

   */

    /// Product → .executable(name: "FooExecutable").
    @Test func executableProduct() async throws {
        try await withPackagePIFBuilders(fromFixture: "PIFBuilder/ExecutableAndLibrary") { packagesAndBuilders, observabilitySystem in
            let packagePifBuilder: PackagePIFBuilder = try #require(packagesAndBuilders.only?.pifBuilder)
            let modulesOrProducts: [PackagePIFBuilder.ModuleOrProduct] = try packagePifBuilder.build()

            let executableProductPIFTarget = try #require(modulesOrProducts.only {
                try $0.name == "FooExecutable" &&
                $0.underlyingPIFTarget.productType == .executable
            })
            let libraryModulePIFTarget = try #require(modulesOrProducts.only {
                try $0.name == "FooLibrary" &&
                $0.underlyingPIFTarget.productType == .commonObject &&
                !$0.underlyingPIFTarget.isVariant(.dynamic)
            })

            #expect(executableProductPIFTarget.type == .executable)
            #expect(executableProductPIFTarget.indexableFileURLs.count == 1)
            #expect(try executableProductPIFTarget.underlyingPIFTarget.id.value.hasPrefix("PACKAGE-PRODUCT:"))
            #expect(try executableProductPIFTarget.underlyingPIFTarget.id.value.hasSuffix(".FooExecutable"))
            #expect(try executableProductPIFTarget.underlyingPIFTarget.name == "FooExecutable-product")
            #expect(try executableProductPIFTarget.underlyingPIFTarget.productType == .executable)
            #expect(try executableProductPIFTarget.underlyingPIFTarget.sourceFiles.count == 1)

            // Links "FooLibrary" target/module.
            #expect(executableProductPIFTarget.linkedPackageBinaries.count == 1)
            #expect(try executableProductPIFTarget.underlyingPIFTarget.linkedTargets == [libraryModulePIFTarget.underlyingPIFTarget.id])
        }
    }
}

// MARK: - Test Helpers

fileprivate func withPackagePIFBuilders(
    fromFixture fixtureName: String,
    addLocalRpaths: Bool = true,
    runTest: ([(package: ResolvedPackage, pifBuilder: PackagePIFBuilder)], TestingObservability) async throws -> ()
) async throws {
    try await fixture(name: fixtureName) { fixturePath in
        let observabilitySystem = ObservabilitySystem.makeForTesting(verbose: false)

        let workspace = try Workspace(
            fileSystem: localFileSystem,
            forRootPackage: fixturePath,
            customManifestLoader: ManifestLoader(toolchain: UserToolchain.default),
            delegate: MockWorkspaceDelegate()
        )
        let graph = try await workspace.loadPackageGraph(
            rootInput: PackageGraphRootInput(packages: [fixturePath], dependencies: []),
            observabilityScope: observabilitySystem.topScope
        )
        let builder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: fixturePath,
                addLocalRpaths: addLocalRpaths
            ),
            fileSystem: localFileSystem,
            observabilityScope: observabilitySystem.topScope
        )
        var keepBuilderDelegatesAround: [any PackagePIFBuilder.BuildDelegate] = []

        let pifBuilders: [(ResolvedPackage, PackagePIFBuilder)] = try await builder.makePIFBuilders(
            buildParameters: mockBuildParameters(destination: .host)
        ).map { (pifBuilder: (ResolvedPackage, PackagePIFBuilder, any PackagePIFBuilder.BuildDelegate)) in
            keepBuilderDelegatesAround.append(pifBuilder.2)
            return (pifBuilder.0, pifBuilder.1)
        }

        try await runTest(pifBuilders, observabilitySystem)
    }
}

// MARK: - PIF Helpers

fileprivate enum PIFError: Error {
    case missingPifTarget
    case unexpectedFileReference
    case unexpectedTargetProductReference
}

fileprivate extension PackagePIFBuilder.ModuleOrProduct {
    var underlyingPIFTarget: ProjectModel.Target {
        get throws {
            switch self.pifTarget {
            case .target(let target):
                return target
            case .none, .aggregate:
                throw PIFError.missingPifTarget
            }
        }
    }
}

fileprivate extension ProjectModel.Target {
    func isVariant(_ targetSuffix: TargetSuffix) -> Bool {
        self.id.hasSuffix(targetSuffix)
    }

    var linkedTargets: [ProjectModel.GUID] {
        get throws {
            var linkedTargets: [ProjectModel.GUID] = []

            for buildPhase in self.buildPhases {
                switch buildPhase {
                case .frameworks(let frameworksBuildPhase):
                    for buildFile in frameworksBuildPhase.files {
                        switch buildFile.ref {
                        case .targetProduct(let targetID):
                            linkedTargets.append(targetID)
                        case .reference:
                            throw PIFError.unexpectedFileReference
                        }
                    }
                default:
                    break
                }
            }
            return linkedTargets
        }
    }

    var sourceFiles: [ProjectModel.GUID] {
        get throws {
            var sourceFiles: [ProjectModel.GUID] = []

            for buildPhase in self.buildPhases {
                switch buildPhase {
                case .sources(let sourcesPhase):
                    for buildFile in sourcesPhase.files {
                        switch buildFile.ref {
                        case .reference(let fileID):
                            sourceFiles.append(fileID)
                        case .targetProduct:
                            throw PIFError.unexpectedTargetProductReference
                        }
                    }
                default:
                    break
                }
            }
            return sourceFiles
        }
    }
}
