//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _InternalTestSupport
import Basics
import Foundation
import PackageGraph
import PackageModel
@testable import SBOMModel

import struct TSCUtility.Version

enum SBOMTestStore {
    static let swiftPMRevision = "e535ac05e3ec765611044bdafa9703db3f67ac07"
    static let swiftPMURL = "https://github.com/swiftlang/swift-package-manager.git"

    static let swiftlyRevision = "985e34f447d55854f2212f5112ef2d344a7e2072"
    static let swiftlyURL = "https://github.com/swiftlang/swiftly.git"

    private static let spmDependencies = [
        ("swift-system", "https://github.com/apple/swift-system.git", "1.3.2"),
        ("swift-collections", "https://github.com/apple/swift-collections.git", "1.1.4"),
        ("swift-argument-parser", "https://github.com/apple/swift-argument-parser.git", "1.5.1"),
        ("swift-toolchain-sqlite", "https://github.com/swiftlang/swift-toolchain-sqlite.git", "1.0.0"),
        ("swift-llbuild", "https://github.com/swiftlang/swift-llbuild.git", "swift-6.0-branch"),
        ("swift-tools-support-core", "https://github.com/swiftlang/swift-tools-support-core.git", "main"),
        ("swift-driver", "https://github.com/swiftlang/swift-driver.git", "main"),
        ("swift-asn1", "https://github.com/apple/swift-asn1.git", "1.2.0"),
        ("swift-crypto", "https://github.com/apple/swift-crypto.git", "3.0.0"),
        ("swift-certificates", "https://github.com/apple/swift-certificates.git", "1.5.0"),
    ]

    private static let swiftlyDependencies = [
        ("swift-system", "https://github.com/apple/swift-system.git", "1.4.2"),
        ("swift-subprocess", "https://github.com/swiftlang/swift-subprocess.git", "1.0.0"),
        ("swift-argument-parser", "https://github.com/apple/swift-argument-parser.git", "1.3.0"),
        ("swift-tools-support-core", "https://github.com/swiftlang/swift-tools-support-core.git", "0.7.2"),
        ("swift-collections", "https://github.com/apple/swift-collections.git", "1.1.4"),
        ("swift-numerics", "https://github.com/apple/swift-numerics.git", "1.0.2"),
        ("swift-algorithms", "https://github.com/apple/swift-algorithms.git", "1.2.0"),
        ("swift-atomics", "https://github.com/apple/swift-atomics.git", "1.2.0"),
        ("async-http-client", "https://github.com/swift-server/async-http-client.git", "1.24.0"),
        (
            "swift-openapi-async-http-client",
            "https://github.com/swift-server/swift-openapi-async-http-client.git",
            "1.1.0"
        ),
        ("swift-nio", "https://github.com/apple/swift-nio.git", "2.80.0"),
        ("swift-openapi-runtime", "https://github.com/apple/swift-openapi-runtime.git", "1.8.2"),
    ]

    private static func createResolvedPackagesStore(
        name: String,
        url: String,
        revision: String,
        dependencies: [(String, String, String)]
    ) throws -> ResolvedPackagesStore {
        let store = try createBaseStore(filename: "\(name)-Package.resolved")
        try addRemoteRepository(
            to: store,
            name: name,
            url: url,
            revision: revision
        )
        try addDependencies(dependencies, to: store)
        return store
    }

    package static func createSPMResolvedPackagesStore() throws -> ResolvedPackagesStore {
        try self.createResolvedPackagesStore(
            name: "swift-package-manager",
            url: self.swiftPMURL,
            revision: self.swiftPMRevision,
            dependencies: self.spmDependencies
        )
    }

    package static func createSwiftlyResolvedPackagesStore() throws -> ResolvedPackagesStore {
        try self.createResolvedPackagesStore(
            name: "swiftly",
            url: self.swiftlyURL,
            revision: self.swiftlyRevision,
            dependencies: self.swiftlyDependencies
        )
    }

    package static func createSimpleResolvedPackagesStore() throws -> ResolvedPackagesStore {
        try self.createResolvedPackagesStore(
            name: "MyApp",
            url: "https://github.com/example/myapp.git",
            revision: "abc123def456abc123def456abc123def456abc1",
            dependencies: [
                ("Utils", "https://github.com/example/utils.git", "1.0.0"),
            ]
        )
    }

    private static func createBaseStore(filename: String) throws -> ResolvedPackagesStore {
        let fs = InMemoryFileSystem()
        let packageResolvedFile = AbsolutePath("/tmp/\(filename)")

        return try ResolvedPackagesStore(
            packageResolvedFile: packageResolvedFile,
            workingDirectory: .root,
            fileSystem: fs,
            mirrors: .init()
        )
    }

    private static func addRemoteRepository(
        to store: ResolvedPackagesStore,
        name: String,
        url: String,
        revision: String
    ) throws {
        let identity = PackageIdentity.plain(name)
        let packageRef = PackageReference.remoteSourceControl(
            identity: identity,
            url: SourceControlURL(url)
        )

        store.track(
            packageRef: packageRef,
            state: .revision(revision)
        )
    }

    private static func addDependencies(
        _ dependencies: [(String, String, String)],
        to store: ResolvedPackagesStore
    ) throws {
        for (name, url, version) in dependencies {
            let identity = PackageIdentity.plain(name)
            let packageRef = PackageReference.remoteSourceControl(
                identity: identity,
                url: SourceControlURL(url)
            )

            let mockRevision = self.generateMockRevision(for: name)
            let state = try createResolutionState(version: version, revision: mockRevision)

            store.track(packageRef: packageRef, state: state)
        }
    }

    private static func createResolutionState(
        version: String,
        revision: String
    ) throws -> ResolvedPackagesStore.ResolutionState {
        // Try to parse as a version first
        if let parsedVersion = try? Version(versionString: version) {
            .version(parsedVersion, revision: revision)
        } else {
            // If it can't be parsed as a version, treat it as a branch
            .branch(name: version, revision: revision)
        }
    }

    package static func generateMockRevision(for packageName: String) -> String {
        let hash = packageName.hash
        return String(format: "%040x", abs(hash)).prefix(40).padding(toLength: 40, withPad: "0", startingAt: 0)
    }
}
