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
        .issue("https://github.com/swiftlang/swift-build/issues/609", relationship: .defect),
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func moduleDirectDeps1(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        let configuration = data.config

        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "ModuleAliasing/DirectDeps1") { fixturePath in
                let pkgPath = fixturePath.appending(components: "AppPkg")
                let buildPath = try pkgPath.appending(components: buildSystem.binPath(for: configuration))
                let expectedModules = [
                    "GameUtils.swiftmodule",
                    "Utils.swiftmodule",
                ]
                try await executeSwiftBuild(
                    pkgPath,
                    configuration: configuration,
                    extraArgs: ["--vv"],
                    buildSystem: buildSystem,
                )

                expectFileExists(at: buildPath.appending(components: executableName("App")))
                for file in expectedModules {
                    switch buildSystem {
                    case .native:
                        expectFileExists(at: buildPath.appending(components: "Modules", file))
                    case .swiftbuild:
                        expectFileExists(at: buildPath.appending(components: file))
                    case .xcode:
                        Issue.record("expectations are not implemented")
                    }
                }
                _ = try await executeSwiftBuild(
                    pkgPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/9130", relationship: .fixedBy),
        .IssueWindowsLongPath,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func moduleDirectDeps2(
        data: BuildData
    ) async throws {
        let buildSystem = data.buildSystem
        let configuration = data.config
        try await withKnownIssue(isIntermittent: true) {
            try await fixture(name: "ModuleAliasing/DirectDeps2") { fixturePath in
                let pkgPath = fixturePath.appending(components: "AppPkg")
                let buildPath = try pkgPath.appending(components: buildSystem.binPath(for: configuration))
                let expectedModules = [
                    "AUtils.swiftmodule",
                    "BUtils.swiftmodule",
                ]
                try await executeSwiftBuild(
                    pkgPath,
                    configuration: configuration,
                    extraArgs: ["--vv"],
                    buildSystem: buildSystem,
                )
                expectFileExists(at: buildPath.appending(components: executableName("App")))
                for file in expectedModules {
                    switch buildSystem {
                    case .native:
                        expectFileExists(at: buildPath.appending(components: "Modules", file))
                    case .swiftbuild:
                        expectFileExists(at: buildPath.appending(components: file))
                    case .xcode:
                        Issue.record("expectations are not implemented")
                    }
                }
                _ = try await executeSwiftBuild(
                    pkgPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/9130", relationship: .fixedBy),
        .IssueWindowsLongPath,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func moduleNestedDeps1(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        let configuration = data.config
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "ModuleAliasing/NestedDeps1") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = try pkgPath.appending(components: buildSystem.binPath(for: configuration))
            let expectedModules = [
                "A.swiftmodule",
                "AFooUtils.swiftmodule",
                "CarUtils.swiftmodule",
                "X.swiftmodule",
                "XFooUtils.swiftmodule",
                "XUtils.swiftmodule",
            ]
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            for file in expectedModules {
                switch buildSystem {
                case .native:
                    expectFileExists(at: buildPath.appending(components: "Modules", file))
                case .swiftbuild:
                    expectFileExists(at: buildPath.appending(components: file))
                case .xcode:
                    Issue.record("expectations are not implemented")
                }
            }

            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }

    @Test(
        .issue("https://github.com/swiftlang/swift-package-manager/issues/8987", relationship: .defect),
        .issue("https://github.com/swiftlang/swift-package-manager/pull/9130", relationship: .fixedBy),
        .IssueWindowsLongPath,
        .IssueWindowsCannotSaveAttachment,
        .tags(
            Tag.Feature.Command.Build,
        ),
        arguments: getBuildData(for: SupportedBuildSystemOnAllPlatforms),
    )
    func moduleNestedDeps2(
        data: BuildData,
    ) async throws {
        let buildSystem = data.buildSystem
        let configuration = data.config
        try await withKnownIssue(isIntermittent: true) {
        try await fixture(name: "ModuleAliasing/NestedDeps2") { fixturePath in
            let pkgPath = fixturePath.appending(components: "AppPkg")
            let buildPath = try pkgPath.appending(components: buildSystem.binPath(for: configuration))
            try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                extraArgs: ["--vv"],
                buildSystem: buildSystem,
            )
            let expectedModules = [
                "A.swiftmodule",
                "BUtils.swiftmodule",
                "CUtils.swiftmodule",
                "XUtils.swiftmodule",
            ]
            expectFileExists(at: buildPath.appending(components: executableName("App")))
            for file in expectedModules {
                switch buildSystem {
                case .native:
                    expectFileExists(at: buildPath.appending(components: "Modules", file))
                case .swiftbuild:
                    expectFileExists(at: buildPath.appending(components: file))
                case .xcode:
                    Issue.record("expectations are not implemented")
                }
            }
            _ = try await executeSwiftBuild(
                pkgPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            ProcessInfo.hostOperatingSystem == .windows && buildSystem == .swiftbuild
        }
    }
}
