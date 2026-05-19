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
import PackageGraph
import PackageModel
import SourceControl
@testable import Workspace
import XCTest

import struct TSCUtility.Version

final class WorkspacePrefetchTests: XCTestCase {

    /// Fresh checkout (no Package.resolved on disk): prefetchPackages falls
    /// back to the version/range remote deps from root manifests.
    func testPrefetchPackagesFromRootManifestsOnFreshCheckout() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mockWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [MockTarget(name: "Foo", dependencies: [.product(name: "Bar", package: "bar")])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [MockTarget(name: "Bar")],
                    products: [MockProduct(name: "Bar", modules: ["Bar"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        let prefetched = workspace.prefetchPackages(
            rootManifests: rootManifests,
            observabilityScope: observability.topScope
        )

        XCTAssertEqual(prefetched.map(\.identity.description).sorted(), ["bar"])
        XCTAssertNoDiagnostics(observability.diagnostics)
    }

    /// Branch and revision dependencies in root manifests must NOT be
    /// prefetched — only exact/range version requirements are eligible.
    func testPrefetchPackagesSkipsBranchAndRevisionRootDeps() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mockWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [MockTarget(name: "Foo", dependencies: [
                        .product(name: "Versioned", package: "versioned"),
                        .product(name: "Branched", package: "branched"),
                    ])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/versioned", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://scm.com/org/branched", requirement: .branch("main")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Versioned",
                    url: "https://scm.com/org/versioned",
                    targets: [MockTarget(name: "Versioned")],
                    products: [MockProduct(name: "Versioned", modules: ["Versioned"])],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Branched",
                    url: "https://scm.com/org/branched",
                    targets: [MockTarget(name: "Branched")],
                    products: [MockProduct(name: "Branched", modules: ["Branched"])],
                    versions: ["main"]
                ),
            ]
        )

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        let prefetched = workspace.prefetchPackages(
            rootManifests: rootManifests,
            observabilityScope: observability.topScope
        )

        // Only the version-pinned dep should be prefetched.
        XCTAssertEqual(prefetched.map(\.identity.description).sorted(), ["versioned"])
    }

    /// When Package.resolved exists, prefetchPackages reads the full
    /// transitive closure from disk and prefers it over root manifest deps.
    func testPrefetchPackagesPrefersResolvedFileOverRootManifests() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mockWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [MockTarget(name: "Foo", dependencies: ["Bar"])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [MockTarget(name: "Bar", dependencies: ["Baz"])],
                    products: [MockProduct(name: "Bar", modules: ["Bar"])],
                    dependencies: [
                        .sourceControl(path: "./Baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Baz",
                    targets: [MockTarget(name: "Baz")],
                    products: [MockProduct(name: "Baz", modules: ["Baz"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Resolve once to populate Package.resolved with the full closure.
        try await mockWorkspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        let prefetched = workspace.prefetchPackages(
            rootManifests: rootManifests,
            observabilityScope: observability.topScope
        )

        // The resolved file should expose the full transitive closure
        // (Bar AND Baz), not just the direct root dep.
        let identities = Set(prefetched.map(\.identity.description))
        XCTAssertTrue(identities.contains("bar"), "expected bar in \(identities)")
        XCTAssertTrue(identities.contains("baz"), "expected baz in \(identities)")
    }

    /// `prefetchContainers` excludes packages currently in `.edited` state —
    /// the user's local edit must take precedence over a prefetched container.
    func testPrefetchContainersExcludesEditedPackages() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mockWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [MockTarget(name: "Foo", dependencies: ["Bar"])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        .sourceControl(path: "./Bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    targets: [MockTarget(name: "Bar")],
                    products: [MockProduct(name: "Bar", modules: ["Bar"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Resolve and edit Bar.
        try await mockWorkspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }
        try await mockWorkspace.checkEdit(packageIdentity: "bar") { diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        let (packagesToWarm, prefetched) = await workspace.prefetchContainers(
            rootManifests: rootManifests,
            observabilityScope: observability.topScope
        )

        // Bar is edited — must not appear in either output.
        XCTAssertFalse(
            packagesToWarm.contains { $0.identity.description == "bar" },
            "edited package 'bar' must not be in packagesToWarm"
        )
        XCTAssertFalse(
            prefetched.keys.contains { $0.identity.description == "bar" },
            "edited package 'bar' must not be in prefetched containers"
        )
    }
}
