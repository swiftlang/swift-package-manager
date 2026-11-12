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

import Basics
import Foundation
import PackageAudit
import PackageLoading
import PackageModel
import Testing
import _InternalTestSupport

@_spi(DontAdoptOutsideOfSwiftPMExposedForBenchmarksAndTestsOnly)
import PackageGraph

@testable
import Commands

import struct TSCUtility.Version

struct AuditInputBuilderTests {
    private static let registryURL = URL(string: "https://registry.example.com")!

    private func emptyResolvedPackages(_ fs: FileSystem) throws -> ResolvedPackagesStore {
        try ResolvedPackagesStore(
            packageResolvedFile: "/Root/Package.resolved",
            workingDirectory: "/Root/.build",
            fileSystem: fs,
            mirrors: .init()
        )
    }

    @Test
    func diamondPathsRegistryAndLocalDependencies() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Root/Sources/Root/root.swift",
            "/A/Sources/A/a.swift",
            "/B/Sources/B/b.swift",
            "/C/Sources/C/c.swift",
            "/Reg/Sources/Reg/reg.swift",
            "/Loc/Sources/Loc/loc.swift"
        )
        try RegistryReleaseMetadataStorage.save(
            RegistryReleaseMetadata(
                source: .registry(Self.registryURL),
                metadata: .init(scmRepositoryURLs: [SourceControlURL("https://github.com/example/reg.git")]),
                signature: nil
            ),
            to: "/Reg/\(RegistryReleaseMetadataStorage.fileName)",
            fileSystem: fs
        )

        let observability = ObservabilitySystem.makeForTesting()
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/A", requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/B", requirement: .upToNextMajor(from: "1.0.0")),
                        .registry(identity: "acme.reg", requirement: .upToNextMajor(from: "1.0.0")),
                        .fileSystem(path: "/Loc"),
                    ],
                    targets: [TargetDescription(name: "Root")]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "A",
                    path: "/A",
                    dependencies: [.localSourceControl(path: "/C", requirement: .upToNextMajor(from: "1.0.0"))],
                    targets: [TargetDescription(name: "A")]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "B",
                    path: "/B",
                    dependencies: [.localSourceControl(path: "/C", requirement: .upToNextMajor(from: "1.0.0"))],
                    targets: [TargetDescription(name: "B")]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "C",
                    path: "/C",
                    targets: [TargetDescription(name: "C")]
                ),
                Manifest.createRegistryManifest(
                    displayName: "Reg",
                    identity: .plain("acme.reg"),
                    path: "/Reg",
                    targets: [TargetDescription(name: "Reg")]
                ),
                Manifest.createFileSystemManifest(
                    displayName: "Loc",
                    path: "/Loc",
                    targets: [TargetDescription(name: "Loc")]
                ),
            ],
            observabilityScope: observability.topScope
        )

        let store = try emptyResolvedPackages(fs)
        store.track(
            packageRef: .localSourceControl(identity: .plain("c"), path: "/C"),
            state: .version(Version(1, 2, 3), revision: "abc")
        )
        store.track(
            packageRef: .registry(identity: .plain("acme.reg")),
            state: .version(Version(2, 0, 0), revision: nil)
        )
        store.track(
            packageRef: .remoteSourceControl(
                identity: .plain("gone"),
                url: SourceControlURL("https://github.com/example/gone.git")
            ),
            state: .branch(name: "main", revision: "deadbeef")
        )

        // A local repository whose path needs escaping in a URL.
        store.track(
            packageRef: .localSourceControl(identity: .plain("escaped"), path: "/Repos #1/D"),
            state: .version(Version(1, 0, 0), revision: "def")
        )

        let packages = AuditInputBuilder.makePackages(graph: graph, resolvedPackages: store)
        let byID = Dictionary(uniqueKeysWithValues: packages.map { ($0.identity, $0) })

        #expect(byID[.plain("root")] == nil)

        let escaped = try #require(byID[.plain("escaped")])
        guard case .sourceControl(let escapedURL) = escaped.kind else {
            Issue.record("expected a source control package, got \(escaped.kind)")
            return
        }
        let parsed = try #require(URL(string: escapedURL))
        #expect(parsed.isFileURL)
        #expect(try AbsolutePath(validating: parsed.path) == AbsolutePath("/Repos #1/D"))

        let c = try #require(byID[.plain("c")])
        #expect(c.kind == .sourceControl(url: URL(fileURLWithPath: AbsolutePath("/C").pathString, isDirectory: false).absoluteString))
        #expect(c.state == .version(Version(1, 2, 3)))
        #expect(Set(c.paths) == [["Root", "A", "C"], ["Root", "B", "C"]])
        #expect(c.paths.count == 2)

        let reg = try #require(byID[.plain("acme.reg")])
        #expect(reg.kind == .registry(identity: .plain("acme.reg"), registryURL: Self.registryURL))
        #expect(reg.state == .version(Version(2, 0, 0)))
        #expect(reg.repositoryURLs == ["https://github.com/example/reg.git"])
        #expect(reg.paths == [["Root", "Reg"]])

        let loc = try #require(byID[.plain("loc")])
        #expect(loc.kind == .local(path: "/Loc"))
        #expect(loc.state == .none)
        #expect(loc.paths == [["Root", "Loc"]])

        // Pins that are not part of the graph are still audited, without paths.
        let gone = try #require(byID[.plain("gone")])
        #expect(gone.kind == .sourceControl(url: "https://github.com/example/gone.git"))
        #expect(gone.state == .revision("deadbeef"))
        #expect(gone.paths == [])
    }

    @Test
    func traitGatedDependencyIsPresentWhenAllTraitsEnabled() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Root/Sources/Root/root.swift",
            "/Opt/Sources/Opt/opt.swift"
        )
        let manifests = try [
            Manifest.createRootManifest(
                displayName: "Root",
                path: "/Root",
                toolsVersion: .v5_9,
                dependencies: [.localSourceControl(path: "/Opt", requirement: .upToNextMajor(from: "1.0.0"))],
                targets: [
                    TargetDescription(
                        name: "Root",
                        dependencies: [
                            .product(name: "Opt", package: "Opt", condition: .init(traits: ["Extra"])),
                        ]
                    ),
                ],
                traits: [.init(name: "default"), "Extra"],
                pruneDependencies: true
            ),
            Manifest.createLocalSourceControlManifest(
                displayName: "Opt",
                path: "/Opt",
                products: [.init(name: "Opt", type: .library(.automatic), targets: ["Opt"])],
                targets: [TargetDescription(name: "Opt")]
            ),
        ]

        let withDefaults = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: ObservabilitySystem.makeForTesting().topScope
        )
        let withAll = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: ObservabilitySystem.makeForTesting().topScope,
            enabledTraitsMap: ["Root": ["Extra"]]
        )

        let store = try emptyResolvedPackages(fs)
        let defaultPackages = AuditInputBuilder.makePackages(graph: withDefaults, resolvedPackages: store)
        let allPackages = AuditInputBuilder.makePackages(graph: withAll, resolvedPackages: store)

        // Without the trait the dependency edge is pruned, so Opt is not reachable from the root.
        #expect(defaultPackages.first { $0.identity == .plain("opt") }?.paths ?? [] == [])
        let opt = try #require(allPackages.first { $0.identity == .plain("opt") })
        #expect(opt.paths == [["Root", "Opt"]])
    }

    @Test
    func statesRemoteSourceControlAndDeterministicOrder() throws {
        let fs = InMemoryFileSystem(
            emptyFiles:
                "/Root/Sources/Root/root.swift",
            "/Zed/Sources/Zed/z.swift",
            "/Remote/Sources/Remote/r.swift",
            "/Branchy/Sources/Branchy/b.swift"
        )
        let remoteURL = SourceControlURL("https://github.com/example/remote.git")
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: [
                Manifest.createRootManifest(
                    displayName: "Root",
                    path: "/Root",
                    dependencies: [
                        .localSourceControl(path: "/Zed", requirement: .upToNextMajor(from: "1.0.0")),
                        .remoteSourceControl(url: remoteURL, requirement: .upToNextMajor(from: "1.0.0")),
                        .localSourceControl(path: "/Branchy", requirement: .upToNextMajor(from: "1.0.0")),
                    ],
                    targets: [TargetDescription(name: "Root")]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Zed", path: "/Zed", targets: [TargetDescription(name: "Zed")]
                ),
                Manifest.createRemoteSourceControlManifest(
                    displayName: "Remote", url: remoteURL, path: "/Remote",
                    targets: [TargetDescription(name: "Remote")]
                ),
                Manifest.createLocalSourceControlManifest(
                    displayName: "Branchy", path: "/Branchy", targets: [TargetDescription(name: "Branchy")]
                ),
            ],
            observabilityScope: ObservabilitySystem.makeForTesting().topScope
        )

        let store = try emptyResolvedPackages(fs)
        store.track(
            packageRef: .localSourceControl(identity: .plain("branchy"), path: "/Branchy"),
            state: .branch(name: "main", revision: "cafe")
        )
        store.track(
            packageRef: .remoteSourceControl(identity: .plain("remote"), url: remoteURL),
            state: .revision("f00d")
        )
        store.track(
            packageRef: .remoteSourceControl(
                identity: .plain("aaa-gone"),
                url: SourceControlURL("https://github.com/example/aaa-gone.git")
            ),
            state: .revision("1111")
        )

        let packages = AuditInputBuilder.makePackages(graph: graph, resolvedPackages: store)
        // Graph packages sorted by identity first, then pins that are not in the graph.
        #expect(packages.map(\.identity.description) == ["branchy", "remote", "zed", "aaa-gone"])

        #expect(packages[0].state == .revision("cafe"))
        #expect(packages[1].kind == .sourceControl(url: remoteURL.absoluteString))
        #expect(packages[1].state == .revision("f00d"))
        #expect(packages[2].state == .none)
    }

    @Test
    func deepDiamondChainIsPrunedAndCapped() throws {
        let count = 25
        var files = ["/Root/Sources/Root/root.swift"]
        var manifests = [Manifest]()
        func dep(_ name: String) -> PackageDependency {
            .localSourceControl(path: AbsolutePath("/\(name)"), requirement: .upToNextMajor(from: "1.0.0"))
        }
        func add(_ name: String, _ deps: [String]) throws {
            files.append("/\(name)/Sources/\(name)/x.swift")
            manifests.append(try Manifest.createLocalSourceControlManifest(
                displayName: name,
                path: AbsolutePath("/\(name)"),
                dependencies: deps.map(dep),
                targets: [TargetDescription(name: name)]
            ))
        }
        manifests.append(try Manifest.createRootManifest(
            displayName: "Root",
            path: "/Root",
            dependencies: [dep("D0")],
            targets: [TargetDescription(name: "Root")]
        ))
        for i in 0..<count {
            try add("D\(i)", ["L\(i)", "R\(i)"])
            try add("L\(i)", ["D\(i + 1)"])
            try add("R\(i)", ["D\(i + 1)"])
        }
        try add("D\(count)", [])

        let fs = InMemoryFileSystem(emptyFiles: files)
        let graph = try loadModulesGraph(
            fileSystem: fs,
            manifests: manifests,
            observabilityScope: ObservabilitySystem.makeForTesting().topScope
        )
        let store = try emptyResolvedPackages(fs)

        let start = ContinuousClock.now
        let packages = AuditInputBuilder.makePackages(graph: graph, resolvedPackages: store)
        let elapsed = ContinuousClock.now - start

        let deepest = try #require(packages.first { $0.identity.description == "d\(count)" })
        #expect(deepest.paths.count == AuditInputBuilder.maxPathsPerPackage)
        #expect(elapsed < .seconds(5))
    }
}
