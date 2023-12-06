//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import Build
import LLBuildManifest
import PackageGraph
import PackageModel
import struct SPMBuildCore.BuildParameters
import SPMTestSupport
import class TSCBasic.InMemoryFileSystem
import XCTest

final class LLBuildManifestBuilderTests: XCTestCase {
    func testCreateProductCommand() throws {
        let pkg = AbsolutePath("/pkg")
        let fs = InMemoryFileSystem(
            emptyFiles:
            pkg.appending(components: "Sources", "exe", "main.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: .init(validating: pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

        // macOS, release build

        var buildParameters = mockBuildParameters(environment: BuildEnvironment(
            platform: .macOS,
            configuration: .release
        ))
        var plan = try BuildPlan(
            buildParameters: buildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        var result = try BuildPlanResult(plan: plan)
        var buildProduct = try result.buildProduct(for: "exe")

        var llbuild = LLBuildManifestBuilder(
            plan,
            fileSystem: localFileSystem,
            observabilityScope: observability.topScope
        )
        try llbuild.createProductCommand(buildProduct)

        let basicReleaseCommandNames = [
            AbsolutePath("/path/to/build/release/exe.product/Objects.LinkFileList").pathString,
            "<exe-release.exe>",
            "C.exe-release.exe",
        ]

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            basicReleaseCommandNames.sorted()
        )

        // macOS, debug build

        buildParameters = mockBuildParameters(environment: BuildEnvironment(
            platform: .macOS,
            configuration: .debug
        ))
        plan = try BuildPlan(
            buildParameters: buildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        let entitlementsCommandName = "C.exe-debug.exe-entitlements"
        let basicDebugCommandNames = [
            AbsolutePath("/path/to/build/debug/exe.product/Objects.LinkFileList").pathString,
            "<exe-debug.exe>",
            "C.exe-debug.exe",
        ]

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            (basicDebugCommandNames + [
                AbsolutePath("/path/to/build/debug/exe-entitlement.plist").pathString,
                entitlementsCommandName,
            ]).sorted()
        )

        guard let entitlementsCommand = llbuild.manifest.commands[entitlementsCommandName]?.tool as? ShellTool else {
            XCTFail("unexpected entitlements command type")
            return
        }

        XCTAssertEqual(
            entitlementsCommand.inputs,
            [
                .file("/path/to/build/debug/exe", isMutated: true),
                .file("/path/to/build/debug/exe-entitlement.plist"),
            ]
        )
        XCTAssertEqual(
            entitlementsCommand.outputs,
            [
                .virtual("exe-debug.exe-CodeSigning"),
            ]
        )

        // Linux, release build

        buildParameters = mockBuildParameters(environment: BuildEnvironment(
            platform: .linux,
            configuration: .release
        ))
        plan = try BuildPlan(
            buildParameters: buildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            basicReleaseCommandNames.sorted()
        )

        // Linux, debug build

        buildParameters = mockBuildParameters(environment: BuildEnvironment(
            platform: .linux,
            configuration: .debug
        ))
        plan = try BuildPlan(
            buildParameters: buildParameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observability.topScope
        )

        result = try BuildPlanResult(plan: plan)
        buildProduct = try result.buildProduct(for: "exe")

        llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            basicDebugCommandNames.sorted()
        )
    }
}
