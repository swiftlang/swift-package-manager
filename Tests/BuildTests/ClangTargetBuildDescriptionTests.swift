//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import Build
import PackageGraph
import PackageModel
import SPMBuildCore
import SPMTestSupport
import XCTest

final class ClangTargetBuildDescriptionTests: XCTestCase {
    func testClangIndexStorePath() throws {
        let targetDescription = try makeTargetBuildDescription("test")
        XCTAssertTrue(try targetDescription.basicArguments().contains("-index-store-path"))
    }

    func testSwiftCorelibsFoundationIncludeWorkaround() throws {
        let toolchain = MockToolchain(swiftResourcesPath: AbsolutePath("/fake/path/lib/swift"))

        let macosParameters = mockBuildParameters(toolchain: toolchain, targetTriple: .macOS)
        let linuxParameters = mockBuildParameters(toolchain: toolchain, targetTriple: .arm64Linux)
        let androidParameters = mockBuildParameters(toolchain: toolchain, targetTriple: .arm64Android)

        let macDescription = try makeTargetBuildDescription("swift-corelibs-foundation",
                                                            buildParameters: macosParameters)
        XCTAssertFalse(try macDescription.basicArguments().contains("\(macosParameters.toolchain.swiftResourcesPath!)"))

        let linuxDescription = try makeTargetBuildDescription("swift-corelibs-foundation",
                                                              buildParameters: linuxParameters)
        print(try linuxDescription.basicArguments())
        XCTAssertTrue(try linuxDescription.basicArguments().contains("\(linuxParameters.toolchain.swiftResourcesPath!)"))

        let androidDescription = try makeTargetBuildDescription("swift-corelibs-foundation",
                                                                buildParameters: androidParameters)
        XCTAssertTrue(try androidDescription.basicArguments().contains("\(androidParameters.toolchain.swiftResourcesPath!)"))
    }

    private func makeClangTarget() throws -> ClangTarget {
        try ClangTarget(
            name: "dummy",
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            includeDir: .root,
            moduleMapType: .none,
            type: .library,
            path: .root,
            sources: .init(paths: [.root.appending(component: "foo.c")], root: .root),
            usesUnsafeFlags: false
        )
    }

    private func makeResolvedTarget() throws -> ResolvedTarget {
        ResolvedTarget(
            packageIdentity: .plain("dummy"),
            underlying: try makeClangTarget(),
            dependencies: [],
            supportedPlatforms: [],
            platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)
        )
    }

    private func makeTargetBuildDescription(_ packageName: String,
                                            buildParameters: BuildParameters? = nil) throws -> ClangTargetBuildDescription {
        let observability = ObservabilitySystem.makeForTesting(verbose: false)

        let manifest = Manifest.createRootManifest(
            displayName: "dummy",
            toolsVersion: .v5,
            targets: [try TargetDescription(name: "dummy")]
        )

        let target = try makeResolvedTarget()

        let package = Package(identity: .plain(packageName),
                              manifest: manifest,
                              path: .root,
                              targets: [target.underlying],
                              products: [],
                              targetSearchPath: .root,
                              testTargetSearchPath: .root)

        return try ClangTargetBuildDescription(
            package: .init(underlying: package,
                           defaultLocalization: nil,
                           supportedPlatforms: [],
                           dependencies: [],
                           targets: [target],
                           products: [],
                           registryMetadata: nil,
                           platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)),
            target: target,
            toolsVersion: .current,
            buildParameters: buildParameters ?? mockBuildParameters(
                toolchain: try UserToolchain.default,
                indexStoreMode: .on
            ),
            fileSystem: localFileSystem,
            observabilityScope: observability.topScope
        )
    }
}
