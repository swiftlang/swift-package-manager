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

@testable import Build
import Basics
import class TSCBasic.InMemoryFileSystem
import PackageGraph
import PackageModel
import struct SPMBuildCore.BuildParameters
import LLBuildManifest
import SPMTestSupport
import XCTest

final class LLBuildManifestBuilderTests: XCTestCase {
    func testCreateProductCommand() throws {
        let pkg = AbsolutePath("/pkg")
        let fs = InMemoryFileSystem(emptyFiles:
            pkg.appending(components: "Sources", "exe", "main.swift").pathString
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadPackageGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Pkg",
                    path: try .init(validating: pkg.pathString),
                    targets: [
                        TargetDescription(name: "exe"),
                    ]
                ),
            ],
            observabilityScope: observability.topScope
        )

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

        var llbuild = LLBuildManifestBuilder(plan, fileSystem: localFileSystem, observabilityScope: observability.topScope)
        try llbuild.createProductCommand(buildProduct)

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            [
                "/path/to/build/release/exe.product/Objects.LinkFileList",
                "<exe-release.exe>",
                "C.exe-release.exe",
            ]
        )

        buildParameters.debuggingParameters.shouldEnableDebuggingEntitlement = true
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

        let entitlementsCommandName = "C.exe-release.exe-entitlements"

        XCTAssertEqual(
            llbuild.manifest.commands.map(\.key).sorted(),
            [
                "/path/to/build/release/exe-entitlement.plist",
                "/path/to/build/release/exe.product/Objects.LinkFileList",
                "<exe-release.exe>",
                "C.exe-release.exe",
                entitlementsCommandName,
            ]
        )

        guard let entitlementsCommand = llbuild.manifest.commands[entitlementsCommandName]?.tool as? ShellTool else {
            XCTFail("unexpected entitlements command type")
            return
        }

        XCTAssertEqual(
            entitlementsCommand.inputs,
            [
                .file("/path/to/build/release/exe", isMutated: true),
                .file("/path/to/build/release/exe-entitlement.plist")
            ]
        )
        XCTAssertEqual(
            entitlementsCommand.outputs,
            [
                .virtual("exe-release.exe-CodeSigning"),
            ]
        )
    }
}
