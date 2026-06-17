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
                    targets: [MockTarget(name: "Foo", dependencies: [.product(name: "Bar", package: "bar")])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        // Remote: only remote packages are prefetched.
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                    ]
                ),
            ],
            packages: [
                MockPackage(
                    name: "Bar",
                    url: "https://scm.com/org/bar",
                    targets: [MockTarget(name: "Bar", dependencies: [.product(name: "Baz", package: "baz")])],
                    products: [MockProduct(name: "Bar", modules: ["Bar"])],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/baz", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    versions: ["1.0.0"]
                ),
                MockPackage(
                    name: "Baz",
                    url: "https://scm.com/org/baz",
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

        // Resolved file exposes the full closure (Bar AND Baz), not just the direct dep.
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

    /// A package whose root URL changed since `Package.resolved` must not be prefetched (`qux` keeps the list non-empty).
    func testPrefetchPackagesSkipsResolvedEntryWhoseURLChanged() async throws {
        let sandbox = AbsolutePath("/tmp/ws/")
        let fs = InMemoryFileSystem()

        let mockWorkspace = try await MockWorkspace(
            sandbox: sandbox,
            fileSystem: fs,
            roots: [
                MockPackage(
                    name: "Foo",
                    targets: [MockTarget(name: "Foo", dependencies: [
                        .product(name: "Bar", package: "bar"),
                        .product(name: "Qux", package: "qux"),
                    ])],
                    products: [MockProduct(name: "Foo", modules: ["Foo"])],
                    dependencies: [
                        .sourceControl(url: "https://scm.com/org/bar", requirement: .upToNextMajor(from: "1.0.0")),
                        .sourceControl(url: "https://scm.com/org/qux", requirement: .upToNextMajor(from: "1.0.0")),
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
                MockPackage(
                    name: "Qux",
                    url: "https://scm.com/org/qux",
                    targets: [MockTarget(name: "Qux")],
                    products: [MockProduct(name: "Qux", modules: ["Qux"])],
                    versions: ["1.0.0"]
                ),
            ]
        )

        // Resolve once so Package.resolved pins both at their original URLs.
        try await mockWorkspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        // Sanity: with the same URLs, both are prefetched.
        let unchanged = workspace.prefetchPackages(
            rootManifests: rootManifests,
            observabilityScope: observability.topScope
        )
        XCTAssertEqual(unchanged.map(\.identity.description).sorted(), ["bar", "qux"])

        // Bar's URL changed (added `.git`, same identity) — bar dropped, qux stays.
        let changedURL = SourceControlURL("https://scm.com/org/bar.git")
        let changedURLDep = PackageDependency.remoteSourceControl(
            identity: PackageIdentity(url: changedURL),
            nameForTargetDependencyResolutionOnly: nil,
            url: changedURL,
            requirement: .upToNextMajor(from: "1.0.0"),
            productFilter: .everything
        )
        let changed = workspace.prefetchPackages(
            rootManifests: rootManifests,
            rootDependencies: [changedURLDep],
            observabilityScope: observability.topScope
        )
        XCTAssertEqual(
            changed.map(\.identity.description).sorted(), ["qux"],
            "bar's URL changed and must be dropped; qux unchanged and must stay"
        )
    }

    /// A `rootDependencies` override URL wins over the manifest URL; here it matches the resolved URL so `bar` stays.
    func testPrefetchPackagesRootDependenciesOverrideManifestURL() async throws {
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

        // Resolve once so Package.resolved pins `https://scm.com/org/bar`.
        try await mockWorkspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        // Override matches the resolved URL and wins over the manifest: bar stays.
        let overrideURL = SourceControlURL("https://scm.com/org/bar")
        let overrideDep = PackageDependency.remoteSourceControl(
            identity: PackageIdentity(url: overrideURL),
            nameForTargetDependencyResolutionOnly: nil,
            url: overrideURL,
            requirement: .upToNextMajor(from: "1.0.0"),
            productFilter: .everything
        )
        let prefetched = workspace.prefetchPackages(
            rootManifests: rootManifests,
            rootDependencies: [overrideDep],
            observabilityScope: observability.topScope
        )
        XCTAssertEqual(prefetched.map(\.identity.description).sorted(), ["bar"])
    }

    /// A remote-in-`Package.resolved` package overridden to a local path must not be prefetched as remote.
    func testPrefetchPackagesSkipsFileSystemOverrideOfRemoteResolvedEntry() async throws {
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

        // Resolve once so Package.resolved pins the remote `https://scm.com/org/bar`.
        try await mockWorkspace.checkPackageGraph(roots: ["Foo"]) { _, diagnostics in
            XCTAssertNoDiagnostics(diagnostics)
        }

        let workspace = try mockWorkspace.getOrCreateWorkspace()
        let observability = ObservabilitySystem.makeForTesting()
        let rootManifests = try await workspace.loadRootManifests(
            packages: [try mockWorkspace.pathToRoot(withName: "Foo")],
            observabilityScope: observability.topScope
        )

        // Override `bar` to a local path (same identity as the remote resolved entry).
        let overrideDep = PackageDependency.fileSystem(
            identity: PackageIdentity(url: SourceControlURL("https://scm.com/org/bar")),
            nameForTargetDependencyResolutionOnly: nil,
            path: sandbox.appending(components: "pkgs", "Bar"),
            productFilter: .everything
        )
        let prefetched = workspace.prefetchPackages(
            rootManifests: rootManifests,
            rootDependencies: [overrideDep],
            observabilityScope: observability.topScope
        )
        XCTAssertFalse(
            prefetched.contains { $0.identity.description == "bar" },
            "bar is overridden to a local path; it must not be prefetched as remote, got \(prefetched.map(\.identity.description))"
        )
    }
}
