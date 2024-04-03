//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import class Basics.ObservabilitySystem
import class Build.BuildPlan
import class Build.ProductBuildDescription
import class Build.SwiftTargetBuildDescription
import struct Basics.Triple
import class PackageModel.Manifest
import struct PackageModel.TargetDescription
import func SPMTestSupport.loadPackageGraph

import func SPMTestSupport.embeddedCxxInteropPackageGraph

import func SPMTestSupport.macrosPackageGraph

import func SPMTestSupport.mockBuildParameters

import func SPMTestSupport.trivialPackageGraph

import struct SPMTestSupport.BuildPlanResult
import func SPMTestSupport.XCTAssertMatch
import func SPMTestSupport.XCTAssertNoDiagnostics
import class TSCBasic.InMemoryFileSystem

import XCTest

final class CrossCompilationBuildPlanTests: XCTestCase {
    func testEmbeddedWasmTarget() throws {
        var (graph, fs, observabilityScope) = try trivialPackageGraph(pkgRootPath: "/Pkg")

        let triple = try Triple("wasm32-unknown-none-wasm")
        var parameters = mockBuildParameters(targetTriple: triple)
        parameters.linkingParameters.shouldLinkStaticSwiftStdlib = true
        var result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observabilityScope
        ))
        result.checkProductsCount(2)
        // There are two additional targets on non-Apple platforms, for test discovery and
        // test entry point
        result.checkTargetsCount(5)

        let buildPath = result.plan.productsBuildPath
        var appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "app.wasm").pathString,
                "-module-name", "app", "-static-stdlib", "-emit-executable",
                "@\(buildPath.appending(components: "app.product", "Objects.LinkFileList"))",
                "-target", triple.tripleString,
                "-g",
            ]
        )

        (graph, fs, observabilityScope) = try embeddedCxxInteropPackageGraph(pkgRootPath: "/Pkg")

        result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observabilityScope
        ))
        result.checkProductsCount(2)
        // There are two additional targets on non-Apple platforms, for test discovery and
        // test entry point
        result.checkTargetsCount(5)

        appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "app.wasm").pathString,
                "-module-name", "app", "-static-stdlib", "-emit-executable",
                "@\(buildPath.appending(components: "app.product", "Objects.LinkFileList"))",
                "-enable-experimental-feature", "Embedded",
                "-target", triple.tripleString,
                "-g",
            ]
        )
    }

    func testWasmTargetRelease() throws {
        let pkgPath = AbsolutePath("/Pkg")

        let (graph, fs, observabilityScope) = try trivialPackageGraph(pkgRootPath: pkgPath)

        var parameters = mockBuildParameters(
            config: .release, targetTriple: .wasi, linkerDeadStrip: true
        )
        parameters.linkingParameters.shouldLinkStaticSwiftStdlib = true
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observabilityScope
        ))
        let buildPath = result.plan.productsBuildPath

        let appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "app.wasm").pathString,
                "-module-name", "app", "-static-stdlib", "-emit-executable",
                "-Xlinker", "--gc-sections",
                "@\(buildPath.appending(components: "app.product", "Objects.LinkFileList"))",
                "-target", "wasm32-unknown-wasi",
                "-g",
            ]
        )
    }

    func testWASITarget() throws {
        let pkgPath = AbsolutePath("/Pkg")

        let (graph, fs, observabilityScope) = try trivialPackageGraph(pkgRootPath: pkgPath)

        var parameters = mockBuildParameters(targetTriple: .wasi)
        parameters.linkingParameters.shouldLinkStaticSwiftStdlib = true
        let result = try BuildPlanResult(plan: BuildPlan(
            buildParameters: parameters,
            graph: graph,
            fileSystem: fs,
            observabilityScope: observabilityScope
        ))
        result.checkProductsCount(2)
        // There are two additional targets on non-Apple platforms, for test discovery and
        // test entry point
        result.checkTargetsCount(5)

        let buildPath = result.plan.productsBuildPath

        let lib = try result.target(for: "lib").clangTarget()
        XCTAssertEqual(try lib.basicArguments(isCXX: false), [
            "-target", "wasm32-unknown-wasi",
            "-O0", "-DSWIFT_PACKAGE=1", "-DDEBUG=1",
            "-fblocks",
            "-I", pkgPath.appending(components: "Sources", "lib", "include").pathString,
            "-g",
        ])
        XCTAssertEqual(try lib.objects, [buildPath.appending(components: "lib.build", "lib.c.o")])
        XCTAssertEqual(lib.moduleMap, buildPath.appending(components: "lib.build", "module.modulemap"))

        let exe = try result.target(for: "app").swiftTarget().compileArguments()
        XCTAssertMatch(
            exe,
            [
                "-enable-batch-mode", "-Onone", "-enable-testing",
                "-j3", "-DSWIFT_PACKAGE", "-DDEBUG", "-Xcc",
                "-fmodule-map-file=\(buildPath.appending(components: "lib.build", "module.modulemap"))",
                "-Xcc", "-I", "-Xcc", "\(pkgPath.appending(components: "Sources", "lib", "include"))",
                "-module-cache-path", "\(buildPath.appending(components: "ModuleCache"))", .anySequence,
                "-swift-version", "4", "-g", .anySequence,
            ]
        )

        let appBuildDescription = try result.buildProduct(for: "app")
        XCTAssertEqual(
            try appBuildDescription.linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "app.wasm").pathString,
                "-module-name", "app", "-static-stdlib", "-emit-executable",
                "@\(buildPath.appending(components: "app.product", "Objects.LinkFileList"))",
                "-target", "wasm32-unknown-wasi",
                "-g",
            ]
        )

        let executablePathExtension = try appBuildDescription.binaryPath.extension
        XCTAssertEqual(executablePathExtension, "wasm")

        let testBuildDescription = try result.buildProduct(for: "PkgPackageTests")
        XCTAssertEqual(
            try testBuildDescription.linkArguments(),
            [
                result.plan.destinationBuildParameters.toolchain.swiftCompilerPath.pathString,
                "-L", buildPath.pathString,
                "-o", buildPath.appending(components: "PkgPackageTests.wasm").pathString,
                "-module-name", "PkgPackageTests",
                "-emit-executable",
                "@\(buildPath.appending(components: "PkgPackageTests.product", "Objects.LinkFileList"))",
                "-target", "wasm32-unknown-wasi",
                "-g",
            ]
        )

        let testPathExtension = try testBuildDescription.binaryPath.extension
        XCTAssertEqual(testPathExtension, "wasm")
    }
}
