//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import Commands
import Foundation
import PackageGraph
import PackageLoading
import PackageModel
import PackageRegistry
import SourceControl
@_spi(PackageRefactor) import SwiftRefactor
import Testing
import Workspace
import _InternalTestSupport

import struct SPMBuildCore.BuildSystemProvider
import struct TSCUtility.Version

@discardableResult
fileprivate func execute(
    _ args: [String] = [],
    packagePath: AbsolutePath? = nil,
    manifest: String? = nil,
    env: Environment? = nil,
    configuration: BuildConfiguration,
    buildSystem: BuildSystemProvider.Kind
) async throws -> (stdout: String, stderr: String) {
    var environment = env ?? [:]
    if let manifest, let packagePath {
        try localFileSystem.writeFileContents(packagePath.appending("Package.swift"), string: manifest)
    }

    // don't ignore local packages when caching
    environment["SWIFTPM_TESTS_PACKAGECACHE"] = "1"
    return try await executeSwiftPackage(
        packagePath,
        configuration: configuration,
        extraArgs: args,
        env: environment,
        buildSystem: buildSystem,
    )
}

// Helper function to arbitrarily assert on manifest content
private func expectManifest(_ packagePath: AbsolutePath, _ callback: (String) throws -> Void) throws {
    let manifestPath = packagePath.appending("Package.swift")
    expectFileExists(at: manifestPath)
    let contents: String = try localFileSystem.readFileContents(manifestPath)
    try callback(contents)
}

@Suite(
    .tags(
        .Feature.Command.Package.UpgradeDependencies,
    )
)
struct UpgradeDependenciesCommandTests {
    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func upgradesFromVersionToLatestTag(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("Bar")

            try GitRepository(path: fixturePath.appending("Foo")).tag(name: "2.0.0")

            // Smoke check that the package doesn't contain a 2.0.0 dependency initially.
            try expectManifest(packageRoot) { contents in
                #expect(!contents.contains(#"from: "2.0.0""#))
            }

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents.contains(#"from: "2.0.0""#))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func upgradeTwoDependenciesToLatestTag(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Complex", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("deck-of-playing-cards")

            try GitRepository(path: fixturePath.appending("PlayingCard")).tag(name: "2.0.0")
            try GitRepository(path: fixturePath.appending("FisherYates")).tag(name: "3.0.0")

            // Smoke check that the manifest is on the pre-upgrade versions.
            try expectManifest(packageRoot) { contents in
                #expect(!contents.contains(#"from: "2.0.0""#))
                #expect(!contents.contains(#"from: "3.0.0""#))
            }

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents.contains(#".package(url: "../PlayingCard", from: "2.0.0")"#))
                #expect(contents.contains(#".package(url: "../FisherYates", from: "3.0.0")"#))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func skipsPreReleasesWhenCurrentVersionIsRelease(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let foo = GitRepository(path: fixturePath.appending("Foo"))

            // Publish a pre-release on top of the fixture's 1.2.3 tag.
            try foo.commit(allowEmpty: true)
            try foo.tag(name: "2.0.0-alpha.1")

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents.contains(#"from: "1.2.3""#))
                #expect(!contents.contains("2.0.0-alpha.1"))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func picksUpPreReleasesWhenCurrentVersionIsPreRelease(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let foo = GitRepository(path: fixturePath.appending("Foo"))

            // Rewrite the client manifest to depend on a pre-release.
            let manifestPath = packageRoot.appending("Package.swift")
            let original: String = try localFileSystem.readFileContents(manifestPath)
            try localFileSystem.writeFileContents(
                manifestPath,
                string: original.replacingOccurrences(
                    of: #"from: "1.0.0""#,
                    with: #"from: "1.0.0-beta.1""#
                )
            )

            try foo.commit(allowEmpty: true)
            try foo.tag(name: "2.0.0-alpha.1")

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents.contains(#"from: "2.0.0-alpha.1""#))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func picksUpNewlyPublishedTagAfterInitialResolve(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("Bar")

            // Populate `.build/checkouts` with the initial tag.
            _ = try await execute(
                ["resolve"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            // Smoke check that the package doesn't contain a 2.0.0 dependency initially.
            try expectManifest(packageRoot) { contents in
                #expect(!contents.contains(#"from: "2.0.0""#))
            }

            // Publish a new major version upstream after bar has checked out 1.2.3 as the Foo dependency.
            let foo = GitRepository(path: fixturePath.appending("Foo"))
            try foo.commit(allowEmpty: true)
            try foo.tag(name: "2.0.0")

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents.contains(#"from: "2.0.0""#))
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func zeroDependenciesWithNewerVersionLeavesManifestUnchanged(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await fixture(name: "DependencyResolution/External/Simple", createGitRepo: true) { fixturePath in
            let packageRoot = fixturePath.appending("Bar")
            let manifestPath = packageRoot.appending("Package.swift")

            // The fixture ships pinning Foo to `from: "1.0.0"` but the git repo created by `createGitRepo`
            // publishes it as 1.2.3. Bump the pin to 1.2.3 so that there is no newer version to upgrade to.
            let original: String = try localFileSystem.readFileContents(manifestPath)
            let manifest = original.replacingOccurrences(
                of: #"from: "1.0.0""#,
                with: #"from: "1.2.3""#
            )
            try localFileSystem.writeFileContents(manifestPath, string: manifest)

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: packageRoot,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(packageRoot) { contents in
                #expect(contents == manifest)
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func unresolvableDependencyLeavesManifestUnchanged(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let path = tmpPath.appending("PackageB")
            try localFileSystem.createDirectory(path)

            let manifest = """
                // swift-tools-version: 5.9
                import PackageDescription
                let package = Package(
                    name: "client",
                    dependencies: [
                        .package(path: "invalid", from: "1.0.0"),
                    ],
                    targets: [ .target(name: "client", dependencies: [ "library" ]) ]
                )
                """
            try localFileSystem.writeFileContents(path.appending("Package.swift"), string: manifest)

            _ = try await execute(
                ["upgrade-dependencies"],
                packagePath: path,
                configuration: .debug,
                buildSystem: buildSystem,
            )

            try expectManifest(path) { contents in
                #expect(contents == manifest)
            }
        }
    }

    @Test(
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func missingPackageManifestReportsUnknownPackage(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            await expectThrowsCommandExecutionError(
                try await execute(
                    ["upgrade-dependencies"],
                    packagePath: tmpPath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )
            ) { error in
                #expect(error.stderr.contains("Could not find Package.swift"))
            }
        }
    }

    @Test(
        .disabled(if: ProcessInfo.hostOperatingSystem == .windows, "POSIX file permissions don't apply on Windows"),
        arguments: SupportedBuildSystemOnAllPlatforms
    )
    func unreadablePackageManifestReportsCannotFindManifest(
        buildSystem: BuildSystemProvider.Kind
    ) async throws {
        try await testWithTemporaryDirectory { tmpPath in
            let manifestPath = tmpPath.appending("Package.swift")
            try localFileSystem.writeFileContents(
                manifestPath,
                string: """
                    // swift-tools-version: 5.9
                    import PackageDescription
                    let package = Package(name: "client")
                    """
            )

            // Strip every permission bit so the manifest is unreadable to the
            // current user.
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0))],
                ofItemAtPath: manifestPath.pathString
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o644))],
                    ofItemAtPath: manifestPath.pathString
                )
            }

            // Running as root may bypass POSIX read permissions, so the manifest would remain readable and the
            // expected error would not fire. Skip in that case.
            guard !FileManager.default.isReadableFile(atPath: manifestPath.pathString) else {
                return
            }

            await expectThrowsCommandExecutionError(
                try await execute(
                    ["upgrade-dependencies"],
                    packagePath: tmpPath,
                    configuration: .debug,
                    buildSystem: buildSystem,
                )
            ) { error in
                #expect(error.stderr.contains("cannot find package manifest"))
            }
        }
    }

    @Test
    func latestVersionPicksUpNewVersionFromRegistry() async throws {
        // We cannot inject a `MockRegistry` into the setup that runs the upgrade-dependencies command. The above checks
        // already check the whole Package manifest edit path, so just check that `workspace.latestVersion` is able to
        // pick up new versions from a package registry here.
        let fs = InMemoryFileSystem()
        try fs.createMockToolchain()

        let identity = PackageIdentity.plain("scope.name")
        let packagePath = AbsolutePath.root

        let registry = MockRegistry(
            filesystem: fs,
            identityResolver: DefaultIdentityResolver(),
            checksumAlgorithm: MockHashAlgorithm(),
            fingerprintStorage: MockPackageFingerprintStorage(),
            signingEntityStorage: MockPackageSigningEntityStorage()
        )

        let packageSource = InMemoryRegistryPackageSource(
            fileSystem: fs,
            path: .root.appending(components: "registry", "server", identity.description)
        )
        try packageSource.writePackageContent()

        registry.addPackage(identity: identity, versions: ["1.0.0", "2.0.0", "3.1.0"], source: packageSource)

        let workspace = try Workspace._init(
            fileSystem: fs,
            environment: .mockEnvironment,
            location: .init(forRootPackage: packagePath, fileSystem: fs),
            customHostToolchain: .mockHostToolchain(fs),
            customManifestLoader: MockManifestLoader(manifests: [:]),
            customRegistryClient: registry.registryClient
        )
        let observability = ObservabilitySystem.makeForTesting()

        let latest = await workspace.latestVersion(
            of: .registry(identity: "scope.name"),
            currentVersion: "1.0.0",
            observabilityScope: observability.topScope
        )

        #expect(latest == "3.1.0")
        expectNoDiagnostics(observability.diagnostics)
    }
}
