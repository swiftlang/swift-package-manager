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

import Foundation
import Testing
import _InternalTestSupport

import struct Basics.AbsolutePath
import var Basics.localFileSystem
import typealias Basics.TSCAbsolutePath
import enum PackageModel.BuildConfiguration
import struct SPMBuildCore.BuildSystemProvider

@Suite(
    .tags(
        .TestSize.large,
        .Feature.Command.Build,
    ),
)
struct IndexStoreIntegrationTests {
    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
        BuildConfiguration.allCases,
    )
    func explicitlyEnabled(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: configuration,
                extraArgs: ["--enable-index-store"],
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
            let storePath = binPath.appending(components: "index", "store")
            #expect(try !localFileSystem.getDirectoryContents(storePath).isEmpty)
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func implicitlyEnabledViaBuildConfig(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let storePath = binPath.appending(components: "index", "store")
            #expect(try !localFileSystem.getDirectoryContents(storePath).isEmpty)
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func implicitlyDisabledViaBuildConfig(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .release,
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .release,
                buildSystem: buildSystem,
            )
            let storePath = binPath.appending(components: "index", "store")
            #expect(!localFileSystem.exists(storePath))
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms,
    )
    func explicitlyDisabled(
        buildSystem: BuildSystemProvider.Kind,
    ) async throws {
        try await fixture(name: "CFamilyTargets/SwiftCMixed") { fixturePath in
            try await executeSwiftBuild(
                fixturePath,
                configuration: .debug,
                extraArgs: ["--disable-index-store"],
                buildSystem: buildSystem,
            )
            let binPath = try await getBinPath(
                fixturePath,
                configuration: .debug,
                buildSystem: buildSystem,
            )
            let storePath = binPath.appending(components: "index", "store")
            #expect(!localFileSystem.exists(storePath))
        }
    }
}
