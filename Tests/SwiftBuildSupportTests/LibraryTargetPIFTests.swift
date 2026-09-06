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
import PackageLoading
import PackageModel
import SPMBuildCore
import SwiftBuild
import SwiftBuildSupport
import _InternalTestSupport
import Workspace

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly) import PackageGraph

@Suite
struct LibraryTargetPIFTests {
    private static let packageName = "LibraryTargets"
    private static let packagePath = AbsolutePath("/\(packageName)")

    private static let files = [
        "/LibraryTargets/Sources/StaticLibCore/StaticLibCore.swift",
        "/LibraryTargets/Sources/DynamicLibCore/DynamicLibCore.swift",
        "/LibraryTargets/Sources/StaticLib/StaticLib.swift",
        "/LibraryTargets/Sources/DynamicLib/DynamicLib.swift",
        "/LibraryTargets/Sources/AutoLib/AutoLib.swift",
        "/LibraryTargets/Sources/StaticMember/StaticMember.swift",
        "/LibraryTargets/Sources/DynamicMember/DynamicMember.swift",
        "/LibraryTargets/Sources/AutoMember/AutoMember.swift",
        "/LibraryTargets/Sources/Tool/main.swift",
    ]

    private static func targets() throws -> [TargetDescription] {
        [
            // Library targets with sources.
            try TargetDescription(name: "StaticLibCore"),
            try TargetDescription(name: "StaticLib", dependencies: ["StaticLibCore"], type: .library(.static)),
            try TargetDescription(name: "DynamicLibCore"),
            try TargetDescription(name: "DynamicLib", dependencies: ["DynamicLibCore"], type: .library(.dynamic)),
            try TargetDescription(name: "AutoLib", type: .library(.automatic)),

            // Library targets without sources.
            try TargetDescription(name: "StaticMember"),
            try TargetDescription(name: "StaticAggregate", dependencies: ["StaticMember"], type: .library(.static)),
            try TargetDescription(name: "DynamicMember"),
            try TargetDescription(name: "DynamicAggregate", dependencies: ["DynamicMember"], type: .library(.dynamic)),
            try TargetDescription(name: "AutoMember"),
            try TargetDescription(name: "AutoAggregate", dependencies: ["AutoMember"], type: .library(.automatic)),

            try TargetDescription(
                name: "Tool",
                dependencies: [
                    "StaticLib",
                    "DynamicLib",
                    "AutoLib",
                    "StaticAggregate",
                    "DynamicAggregate",
                    "AutoAggregate",
                ],
                type: .executable
            ),
        ]
    }

    private func makeProject(
        files: [String] = LibraryTargetPIFTests.files,
        targets: [TargetDescription],
        products: [ProductDescription] = [],
        dependencies: [PackageDependency] = [],
        dependencyManifests: [Manifest] = [],
        shouldCreateDylibForDynamicProducts: Bool = true
    ) async throws -> SwiftBuildSupport.PIF.Project {
        let fs = InMemoryFileSystem(emptyFiles: files)
        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: dependencyManifests + [
                Manifest.createRootManifest(
                    displayName: Self.packageName,
                    path: Self.packagePath,
                    toolsVersion: .vNext,
                    dependencies: dependencies,
                    products: products,
                    targets: targets,
                ),
            ],
            observabilityScope: observability.topScope,
        )
        #expect(observability.diagnostics.isEmpty, "unexpected diagnostics: \(observability.diagnostics)")

        let pifBuilder = PIFBuilder(
            graph: graph,
            parameters: try PIFBuilderParameters.constructDefaultParametersForTesting(
                temporaryDirectory: AbsolutePath.root.appending("tmp"),
                addLocalRpaths: .always,
                shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
            ),
            fileSystem: fs,
            observabilityScope: observability.topScope,
        )
        let (pif, _) = try await pifBuilder.constructPIF(
            buildParameters: mockBuildParameters(destination: .host, buildSystemKind: .swiftbuild)
        )
        return try pif.workspace.project(named: Self.packageName)
    }

    @Test
    func staticLibraryTargetWithSources() async throws {
        let project = try await makeProject(targets: Self.targets())
        let target = try project.requireStandardTarget(named: "StaticLib")

        #expect(target.productType == .staticArchive)
        #expect(target.dynamicTargetVariantId == nil)
        #expect(target.common.dependencies.map(\.targetId.value).contains("PACKAGE-TARGET:StaticLibCore"))
        #expect(target.linkedTargetIDs.contains("PACKAGE-TARGET:StaticLibCore"))
        let settings = try target.buildConfig(named: .debug).settings
        #expect(settings[.EXECUTABLE_PREFIX] == "lib")
        #expect(settings[.EXECUTABLE_PREFIX, .windows] == "")
        #expect(settings[.SWIFT_LIBRARIES_ONLY] == "YES")
        #expect(settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")
    }

    @Test(arguments: [true, false])
    func dynamicLibraryTargetWithSources(shouldCreateDylibForDynamicProducts: Bool) async throws {
        let project = try await makeProject(
            targets: Self.targets(),
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
        )
        let target = try project.requireStandardTarget(named: "DynamicLib")

        #expect(target.productType == (shouldCreateDylibForDynamicProducts ? .dynamicLibrary : .framework))
        #expect(target.dynamicTargetVariantId == nil)
        #expect(project.underlying.targets.filter { $0.common.name == "DynamicLib" }.count == 1)
        #expect(target.linkedTargetIDs.contains("PACKAGE-TARGET:DynamicLibCore"))
        let settings = try target.buildConfig(named: .debug).settings
        #expect(settings[.SWIFT_LIBRARIES_ONLY] == "YES")
        #expect(settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")
    }

    @Test(arguments: [true, false])
    func automaticLibraryTargetWithSources(shouldCreateDylibForDynamicProducts: Bool) async throws {
        let project = try await makeProject(
            targets: Self.targets(),
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
        )
        let target = try project.requireStandardTarget(named: "AutoLib")
        #expect(target.productType == .commonStaticArchive)
        let settings = try target.buildConfig(named: .debug).settings
        #expect(settings[.SWIFT_LIBRARIES_ONLY] == "YES")
        #expect(settings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")

        let variantID = try #require(target.dynamicTargetVariantId)
        #expect(variantID.value.hasSuffix("-\(TargetSuffix.dynamic.rawValue)"))
        let variant = try project.requireStandardTarget(withID: variantID)
        #expect(variant.productType == (shouldCreateDylibForDynamicProducts ? .dynamicLibrary : .framework))
        #expect(variant.dynamicTargetVariantId == nil)
        let variantSettings = try variant.buildConfig(named: .debug).settings
        #expect(variantSettings[.SWIFT_LIBRARIES_ONLY] == "YES")
        #expect(variantSettings[.SWIFT_DISABLE_PARSE_AS_LIBRARY] == "NO")
    }

    @Test
    func staticAggregateLibraryTarget() async throws {
        let project = try await makeProject(targets: Self.targets())
        let target = try project.requireStandardTarget(named: "StaticAggregate")

        #expect(target.productType == .staticArchive)
        #expect(target.productName == "$(EXECUTABLE_NAME)")

        let settings = try target.buildConfig(named: .debug).settings
        #expect(settings[.TARGET_NAME] == "StaticAggregate")
        #expect(target.common.dependencies.map(\.targetId.value).contains("PACKAGE-TARGET:StaticMember"))
        #expect(target.linkedTargetIDs.contains("PACKAGE-TARGET:StaticMember"))
    }

    @Test(arguments: [true, false])
    func dynamicAggregateLibraryTarget(shouldCreateDylibForDynamicProducts: Bool) async throws {
        let project = try await makeProject(
            targets: Self.targets(),
            shouldCreateDylibForDynamicProducts: shouldCreateDylibForDynamicProducts
        )
        let target = try project.requireStandardTarget(named: "DynamicAggregate")

        if shouldCreateDylibForDynamicProducts {
            #expect(target.productType == .dynamicLibrary)
            #expect(target.productName == "$(EXECUTABLE_NAME)")
        } else {
            #expect(target.productType == .framework)
            #expect(target.productName == "$(WRAPPER_NAME)")
        }
        #expect(target.common.dependencies.map(\.targetId.value).contains("PACKAGE-TARGET:DynamicMember"))
        #expect(target.linkedTargetIDs.contains("PACKAGE-TARGET:DynamicMember"))
    }

    @Test
    func automaticAggregateLibraryTarget() async throws {
        let project = try await makeProject(targets: Self.targets())
        let target = try project.requireStandardTarget(named: "AutoAggregate")
        #expect(target.productType == .packageProduct)
        #expect(target.common.dependencies.map(\.targetId.value).contains("PACKAGE-TARGET:AutoMember"))
        #expect(target.linkedTargetIDs.contains("PACKAGE-TARGET:AutoMember"))
    }

    @Test
    func aggregateLibraryTargetWithTransitiveObjectDeps() async throws {
        let project = try await makeProject(
            files: [
                "/LibraryTargets/Sources/Leaf/Leaf.swift",
                "/LibraryTargets/Sources/Member/Member.swift",
            ],
            targets: [
                TargetDescription(name: "Leaf"),
                TargetDescription(name: "Member", dependencies: ["Leaf"]),
                TargetDescription(name: "Aggregate", dependencies: ["Member"], type: .library(.static)),
            ]
        )
        let target = try project.requireStandardTarget(named: "Aggregate")
        let dependencyIDs = target.common.dependencies.map(\.targetId.value)
        #expect(dependencyIDs.contains("PACKAGE-TARGET:Member"))
        #expect(dependencyIDs.contains("PACKAGE-TARGET:Leaf"))
    }

    @Test
    func aggregateLibraryTargetWithProductDependency() async throws {
        let project = try await makeProject(
            files: [
                "/LibraryTargets/Sources/Member/Member.swift",
                "/Dep/Sources/DepLib/DepLib.swift",
            ],
            targets: [
                TargetDescription(name: "Member"),
                TargetDescription(
                    name: "Aggregate",
                    dependencies: ["Member", .product(name: "DepLib", package: "Dep")],
                    type: .library(.static)
                ),
            ],
            dependencies: [.fileSystem(path: "/Dep")],
            dependencyManifests: [
                Manifest.createFileSystemManifest(
                    displayName: "Dep",
                    path: "/Dep",
                    toolsVersion: .vNext,
                    products: [
                        try ProductDescription(name: "DepLib", type: .library(.automatic), targets: ["DepLib"]),
                    ],
                    targets: [TargetDescription(name: "DepLib")],
                ),
            ]
        )
        let target = try project.requireStandardTarget(named: "Aggregate")
        let dependencyIDs = target.common.dependencies.map(\.targetId.value)
        #expect(dependencyIDs.contains("PACKAGE-TARGET:Member"))
        #expect(dependencyIDs.contains("PACKAGE-PRODUCT:dep_DepLib.DepLib"))
    }

    @Test
    func libraryTargetClient() async throws {
        let project = try await makeProject(targets: Self.targets())
        let tool = try project.requireStandardTarget(named: "Tool-product")
        let dependencyIDs = Set(tool.common.dependencies.map(\.targetId.value))
        for name in [
            "StaticLib",
            "DynamicLib",
            "AutoLib",
            "StaticAggregate",
            "DynamicAggregate",
            "AutoAggregate",
        ] {
            #expect(dependencyIDs.contains("PACKAGE-TARGET:\(name)"), "missing dependency on '\(name)'")
        }
    }

    @Test
    func clientDoesNotLinkTransitiveDependenciesOfLibraryTarget() async throws {
        let project = try await makeProject(targets: Self.targets())
        let tool = try project.requireStandardTarget(named: "Tool-product")
        let dependencyIDs = Set(tool.common.dependencies.map(\.targetId.value))

        for name in [
            "StaticMember",
            "DynamicMember",
            "AutoMember",
            "StaticLibCore",
            "DynamicLibCore",
        ] {
            #expect(!dependencyIDs.contains("PACKAGE-TARGET:\(name)"))
        }
    }

    @Test
    func productsMayNotContainLibraryTargets() async throws {
        let fs = InMemoryFileSystem(emptyFiles: ["/LibraryTargets/Sources/Lib/Lib.swift"])
        let observability = ObservabilitySystem.makeForTesting()
        _ = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: Self.packageName,
                    path: Self.packagePath,
                    toolsVersion: .vNext,
                    products: [
                        try ProductDescription(name: "Lib", type: .library(.automatic), targets: ["Lib"]),
                    ],
                    targets: [
                        TargetDescription(name: "Lib", type: .library(.static)),
                    ],
                ),
            ],
            observabilityScope: observability.topScope,
        )
        testDiagnostics(observability.diagnostics) { result in
            result.check(
                diagnostic: .contains("products may not include library targets"),
                severity: .error
            )
        }
    }
}

extension SwiftBuildSupport.PIF.Project {
    fileprivate func requireStandardTarget(named name: String) throws -> ProjectModel.Target {
        let matches = underlying.targets.filter { target in
            target.common.name == name
                && !TargetSuffix.allCases.contains { suffix in
                    target.common.id.value.hasSuffix("-\(suffix.rawValue)")
                }
        }
        let target = try #require(
            matches.only,
            "expected exactly one target named '\(name)', found \(matches.count); found: \(underlying.targets.map(\.common.name))",
        )
        return try target.asStandardTarget()
    }

    fileprivate func requireStandardTarget(withID id: ProjectModel.GUID) throws -> ProjectModel.Target {
        let target = try #require(
            underlying.targets.first(where: { $0.common.id == id }),
            "no target with ID '\(id.value)'; found: \(underlying.targets.map(\.common.id.value))",
        )
        return try target.asStandardTarget()
    }
}

extension ProjectModel.BaseTarget {
    fileprivate func asStandardTarget() throws -> ProjectModel.Target {
        guard case .target(let standardTarget) = self else {
            throw StringError("target '\(common.name)' is not a standard target")
        }
        return standardTarget
    }
}

extension ProjectModel.Target {
    fileprivate func buildConfig(named name: BuildConfiguration) throws -> ProjectModel.BuildConfig {
        try #require(
            common.buildConfigs.first { $0.name == name.pifConfiguration },
            "no build configuration named '\(name)' in target '\(common.name)'",
        )
    }

    fileprivate var linkedTargetIDs: [String] {
        common.buildPhases.flatMap { phase -> [String] in
            guard case .frameworks(let frameworks) = phase else { return [] }
            return frameworks.common.files.compactMap {
                if case .targetProduct(let id) = $0.ref { id.value } else { nil }
            }
        }
    }
}
