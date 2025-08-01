//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import struct SPMBuildCore.BuildSystemProvider
import Commands
import PackageModel
import SourceControl
import _InternalTestSupport
import Workspace
import Testing

@Suite(
    .tags(
        Tag.TestSize.large,
    ),
)
struct ModuleAliasingFixtureTests {
    @Test(
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func moduleDirectDeps1(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await fixture(name: "ModuleAliasing/DirectDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: [".build", try UserToolchain.default.targetTriple.platformBuildPathComponent] + buildSystem.binPathSuffixes(for: configuration))
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            switch buildSystem {
                case .native:
                    expectFileExists(at: buildPath.appending(components: "Modules", "GameUtils.swiftmodule"))
                    expectFileExists(at: buildPath.appending(components: "Modules", "Utils.swiftmodule"))
                case .swiftbuild:
                    expectFileExists(at: buildPath.appending(components: "GameUtils.swiftmodule"))
                    expectFileExists(at: buildPath.appending(components: "Utils.swiftmodule"))
                case .xcode:
                    #expect(Bool(false), "expectations are not implemented")
            }
            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
    }
    
    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func moduleDirectDeps2(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "ModuleAliasing/DirectDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: [".build", try UserToolchain.default.targetTriple.platformBuildPathComponent] + buildSystem.binPathSuffixes(for: configuration))
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            expectFileExists(at: buildPath.appending(components: "Modules", "AUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "BUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            buildSystem == .swiftbuild
        }
    }
    
    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func moduleNestedDeps1(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "ModuleAliasing/NestedDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: [".build", try UserToolchain.default.targetTriple.platformBuildPathComponent] + buildSystem.binPathSuffixes(for: configuration))
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            expectFileExists(at: buildPath.appending(components: "Modules", "A.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "AFooUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "CarUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "X.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "XFooUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "XUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            buildSystem == .swiftbuild
        }
    }
    
    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func moduleNestedDeps2(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue {
        try await fixture(name: "ModuleAliasing/NestedDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = pkgPath.appending(components: [".build", try UserToolchain.default.targetTriple.platformBuildPathComponent] + buildSystem.binPathSuffixes(for: configuration))
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            expectFileExists(at: buildPath.appending(components: "Modules", "A.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "BUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "CUtils.swiftmodule"))
            expectFileExists(at: buildPath.appending(components: "Modules", "XUtils.swiftmodule"))
            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            buildSystem == .swiftbuild
        }
    }
}
