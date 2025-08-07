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

import Basics
import SourceControl
import _InternalTestSupport
import Testing
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration

@Suite(
    .tags(
        .TestSize.large,
    ),
)
struct VersionSpecificTests {
    /// Functional tests of end-to-end support for version specific dependency resolution.
    @Test(
        .issue("https://github.com/swiftlang/swift-tools-support-core/pull/521", relationship: .fixedBy), // long file path issue
        .tags(
            .Feature.Command.Build,
            .Feature.Command.Package.Reset,
        ),
        arguments: SupportedBuildSystemOnAllPlatforms, BuildConfiguration.allCases,
    )
    func endToEndResolution(
        buildSystem: BuildSystemProvider.Kind,
        configuration: BuildConfiguration,
    ) async throws {
        try await withKnownIssue(isIntermittent: true) {
        try await testWithTemporaryDirectory{ path in
            let fs = localFileSystem

            // Create a repo for the dependency to test against.
            let depPath = path.appending("Dep")
            try fs.createDirectory(depPath)
            initGitRepo(depPath)
            let repo = GitRepository(path: depPath)

            // Create the initial commit.
            try fs.writeFileContents(
                depPath.appending("Package.swift"),
                string: """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Dep",
                        products: [
                            .library(name: "Dep", targets: ["Dep"]),
                        ],
                        targets: [
                            .target(name: "Dep", path: "./")
                        ]
                    )
                    """
            )
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "Initial")
            try repo.tag(name: "1.0.0")

            // Create the version to test against.
            try fs.writeFileContents(
                depPath.appending("Package.swift"),
                // FIXME: We end up filtering this manifest if it has an invalid
                // tools version as they're assumed to be v3 manifests. Should we
                // do something better?
                string: """
                // swift-tools-version:4.2
                NOT_A_VALID_PACKAGE
                """
            )
            try fs.writeFileContents(
                depPath.appending("foo.swift"),
                string: """
                    public func foo() { print("foo\\n") }
                    """
            )
            try repo.stage(file: "Package.swift")
            try repo.stage(file: "foo.swift")
            try repo.commit(message: "Bogus v1.1.0")
            try repo.tag(name: "1.1.0")

            // Create the primary repository.
            let primaryPath = path.appending("Primary")
            try fs.createDirectory(primaryPath, recursive: true)
            try fs.writeFileContents(
                primaryPath.appending("Package.swift"),
                string: """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Primary",
                        dependencies: [
                            .package(url: "../Dep", from: "1.0.0"),
                        ],
                        targets: [
                            .target(name: "Primary", dependencies: ["Dep"], path: "./")
                        ]
                    )
                    """
            )
            // This build should fail, because of the invalid package.
            await #expect(throws: (any Error).self) {
                try await executeSwiftBuild(
                    primaryPath,
                    configuration: configuration,
                    buildSystem: buildSystem,
                )
            }

            // Create a file which requires a version 1.1.0 resolution.
            try fs.writeFileContents(
                primaryPath.appending("main.swift"),
                string: """
                    import Dep
                    Dep.foo()
                    """
            )

            // Create a version-specific tag, which should work.
            try fs.writeFileContents(
                depPath.appending("Package.swift"),
                string: """
                    // swift-tools-version:4.2
                    import PackageDescription
                    let package = Package(
                        name: "Dep",
                        products: [
                            .library(name: "Dep", targets: ["Dep"]),
                        ],
                        targets: [
                            .target(name: "Dep", path: "./")
                        ]
                    )
                    """
            )
            try repo.stage(file: "Package.swift")
            try repo.commit(message: "OK v1.1.0")
            try repo.tag(name: "1.1.0@swift-\(SwiftVersion.current.major)")

            // The build should work now.
            _ = try await executeSwiftPackage(
                primaryPath,
                configuration: configuration,
                extraArgs: ["reset"],
                buildSystem: buildSystem,
            )
            try await executeSwiftBuild(
                primaryPath,
                configuration: configuration,
                buildSystem: buildSystem,
            )
        }
        } when: {
            buildSystem == .swiftbuild && ProcessInfo.hostOperatingSystem == .windows && CiEnvironment.runningInSelfHostedPipeline
        }
    }
}
