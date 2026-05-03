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

// A standalone benchmark for `PubGrubDependencyResolver`. The resolver's
// `processInputs` walks unversioned and revision-based constraints by
// repeatedly fetching containers and reading manifests; in production this
// work is dominated by I/O. To make that cost visible in a synthetic
// benchmark, every container method here can sleep for a configurable
// `--latency-ms` per call. Combined with topology and size knobs, this
// lets hyperfine produce a meaningful before/after comparison when the
// resolver's setup loop is parallelized.

import ArgumentParser
import Basics
import Foundation
import OrderedCollections
import PackageGraph
import PackageModel

import struct TSCUtility.Version

// MARK: - Topology

enum Topology: String, ExpressibleByArgument, CaseIterable {
    case wideUnversioned = "wide-unversioned"
    case wideRevision = "wide-revision"
    case deepUnversioned = "deep-unversioned"
    case deepRevision = "deep-revision"
    case mixed
}

// MARK: - Bench mock

private final class BenchContainer: PackageContainer, @unchecked Sendable {
    let package: PackageReference
    let shouldInvalidatePinnedVersions: Bool = true
    private let unversionedDependencies: [PackageContainerConstraint]
    private let revisionDependencies: [String: [PackageContainerConstraint]]
    private let versionedDependencies: [Version: [PackageContainerConstraint]]
    private let availableVersions: [Version]
    private let latencyNanos: UInt64

    init(
        package: PackageReference,
        unversionedDependencies: [PackageContainerConstraint] = [],
        revisionDependencies: [String: [PackageContainerConstraint]] = [:],
        versionedDependencies: [Version: [PackageContainerConstraint]] = [:],
        availableVersions: [Version] = [],
        latencyNanos: UInt64
    ) {
        self.package = package
        self.unversionedDependencies = unversionedDependencies
        self.revisionDependencies = revisionDependencies
        self.versionedDependencies = versionedDependencies
        self.availableVersions = availableVersions.sorted()
        self.latencyNanos = latencyNanos
    }

    private func sleepIfNeeded() async {
        if latencyNanos > 0 {
            try? await Task.sleep(nanoseconds: latencyNanos)
        }
    }

    func isToolsVersionCompatible(at version: Version) async -> Bool { true }

    func toolsVersion(for version: Version) async throws -> ToolsVersion { .current }

    func toolsVersionsAppropriateVersionsDescending() async throws -> [Version] {
        Array(self.availableVersions.reversed())
    }

    func versionsAscending() async throws -> [Version] {
        self.availableVersions
    }

    func versionsDescending() async throws -> [Version] {
        Array(self.availableVersions.reversed())
    }

    func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: EnabledTraits) async throws -> [PackageContainerConstraint] {
        await self.sleepIfNeeded()
        return self.versionedDependencies[version] ?? []
    }

    func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: EnabledTraits) async throws -> [PackageContainerConstraint] {
        await self.sleepIfNeeded()
        return self.revisionDependencies[revision] ?? []
    }

    func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: EnabledTraits) async throws -> [PackageContainerConstraint] {
        await self.sleepIfNeeded()
        return self.unversionedDependencies
    }

    func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        self.package
    }
}

private struct BenchProvider: PackageContainerProvider {
    let containers: [PackageReference: BenchContainer]
    let latencyNanos: UInt64

    func getContainer(
        for package: PackageReference,
        updateStrategy: ContainerUpdateStrategy,
        observabilityScope: ObservabilityScope
    ) async throws -> PackageContainer {
        if self.latencyNanos > 0 {
            try? await Task.sleep(nanoseconds: self.latencyNanos)
        }
        guard let c = self.containers[package] else {
            throw BenchError.unknownPackage(package.identity.description)
        }
        return c
    }
}

enum BenchError: Error, CustomStringConvertible {
    case unknownPackage(String)
    case resolutionFailed(String)

    var description: String {
        switch self {
        case .unknownPackage(let name): "unknown package: \(name)"
        case .resolutionFailed(let msg): "resolution failed: \(msg)"
        }
    }
}

// MARK: - Graph builders

private let v1: Version = "1.0.0"
private let v2: Version = "2.0.0"
private let v1Range: VersionSetSpecifier = .range(v1 ..< v2)

private struct Graph {
    var containers: [BenchContainer]
    var rootConstraints: [PackageContainerConstraint]
}

private func makeRef(_ name: String) -> PackageReference {
    .localSourceControl(identity: .plain(name), path: try! .init(validating: "/\(name)"))
}

private func wideUnversionedGraph(size: Int, latencyNanos: UInt64) -> Graph {
    var containers: [BenchContainer] = []
    var rootConstraints: [PackageContainerConstraint] = []
    for i in 0 ..< size {
        let parentName = "u\(i)"
        let childName = "uv\(i)"
        let parentRef = makeRef(parentName)
        let childRef = makeRef(childName)
        rootConstraints.append(.init(
            package: parentRef,
            requirement: .unversioned,
            products: .specific([parentName])
        ))
        let parentDep = PackageContainerConstraint(
            package: childRef,
            requirement: .versionSet(v1Range),
            products: .specific([childName])
        )
        containers.append(BenchContainer(
            package: parentRef,
            unversionedDependencies: [parentDep],
            latencyNanos: latencyNanos
        ))
        containers.append(BenchContainer(
            package: childRef,
            versionedDependencies: [v1: []],
            availableVersions: [v1],
            latencyNanos: latencyNanos
        ))
    }
    return Graph(containers: containers, rootConstraints: rootConstraints)
}

private func wideRevisionGraph(size: Int, latencyNanos: UInt64) -> Graph {
    var containers: [BenchContainer] = []
    var rootConstraints: [PackageContainerConstraint] = []
    let revision = "main"
    for i in 0 ..< size {
        let parentName = "r\(i)"
        let childName = "rv\(i)"
        let parentRef = makeRef(parentName)
        let childRef = makeRef(childName)
        rootConstraints.append(.init(
            package: parentRef,
            requirement: .revision(revision),
            products: .specific([parentName])
        ))
        let parentDep = PackageContainerConstraint(
            package: childRef,
            requirement: .versionSet(v1Range),
            products: .specific([childName])
        )
        containers.append(BenchContainer(
            package: parentRef,
            revisionDependencies: [revision: [parentDep]],
            latencyNanos: latencyNanos
        ))
        containers.append(BenchContainer(
            package: childRef,
            versionedDependencies: [v1: []],
            availableVersions: [v1],
            latencyNanos: latencyNanos
        ))
    }
    return Graph(containers: containers, rootConstraints: rootConstraints)
}

private func deepUnversionedGraph(size: Int, latencyNanos: UInt64) -> Graph {
    precondition(size >= 1)
    var containers: [BenchContainer] = []
    let leafName = "leaf"
    let leafRef = makeRef(leafName)
    containers.append(BenchContainer(
        package: leafRef,
        versionedDependencies: [v1: []],
        availableVersions: [v1],
        latencyNanos: latencyNanos
    ))
    var nextDep = PackageContainerConstraint(
        package: leafRef,
        requirement: .versionSet(v1Range),
        products: .specific([leafName])
    )
    for i in stride(from: size - 1, through: 0, by: -1) {
        let name = "u\(i)"
        let ref = makeRef(name)
        containers.append(BenchContainer(
            package: ref,
            unversionedDependencies: [nextDep],
            latencyNanos: latencyNanos
        ))
        nextDep = PackageContainerConstraint(
            package: ref,
            requirement: .unversioned,
            products: .specific([name])
        )
    }
    return Graph(containers: containers, rootConstraints: [nextDep])
}

private func deepRevisionGraph(size: Int, latencyNanos: UInt64) -> Graph {
    precondition(size >= 1)
    var containers: [BenchContainer] = []
    let revision = "main"
    let leafName = "leaf"
    let leafRef = makeRef(leafName)
    containers.append(BenchContainer(
        package: leafRef,
        versionedDependencies: [v1: []],
        availableVersions: [v1],
        latencyNanos: latencyNanos
    ))
    var nextDep = PackageContainerConstraint(
        package: leafRef,
        requirement: .versionSet(v1Range),
        products: .specific([leafName])
    )
    for i in stride(from: size - 1, through: 0, by: -1) {
        let name = "r\(i)"
        let ref = makeRef(name)
        containers.append(BenchContainer(
            package: ref,
            revisionDependencies: [revision: [nextDep]],
            latencyNanos: latencyNanos
        ))
        nextDep = PackageContainerConstraint(
            package: ref,
            requirement: .revision(revision),
            products: .specific([name])
        )
    }
    return Graph(containers: containers, rootConstraints: [nextDep])
}

private func mixedGraph(size: Int, latencyNanos: UInt64) -> Graph {
    let unversionedHalf = wideUnversionedGraph(size: max(1, size / 2), latencyNanos: latencyNanos)
    let revisionHalf = wideRevisionGraph(size: max(1, size - size / 2), latencyNanos: latencyNanos)
    return Graph(
        containers: unversionedHalf.containers + revisionHalf.containers,
        rootConstraints: unversionedHalf.rootConstraints + revisionHalf.rootConstraints
    )
}

// MARK: - Driver

@main
struct ResolverBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-package-resolver-bench",
        abstract: "Microbenchmark harness for PubGrubDependencyResolver."
    )

    @Option(help: "Graph topology to resolve.")
    var topology: Topology

    @Option(help: "Number of top-level dependencies (wide) or chain depth (deep).")
    var size: Int = 10

    @Option(name: .customLong("latency-ms"), help: "Simulated I/O latency per container fetch / dependency read, in milliseconds.")
    var latencyMs: Int = 0

    @Option(help: "Number of resolutions to perform back-to-back. Useful when measuring without hyperfine.")
    var iterations: Int = 1

    @Flag(help: "Suppress all output except the per-iteration elapsed time.")
    var quiet: Bool = false

    func run() async throws {
        precondition(self.size >= 1, "--size must be >= 1")
        precondition(self.iterations >= 1, "--iterations must be >= 1")
        let latencyNanos = UInt64(self.latencyMs) * 1_000_000

        let graph: Graph
        switch self.topology {
        case .wideUnversioned:
            graph = wideUnversionedGraph(size: self.size, latencyNanos: latencyNanos)
        case .wideRevision:
            graph = wideRevisionGraph(size: self.size, latencyNanos: latencyNanos)
        case .deepUnversioned:
            graph = deepUnversionedGraph(size: self.size, latencyNanos: latencyNanos)
        case .deepRevision:
            graph = deepRevisionGraph(size: self.size, latencyNanos: latencyNanos)
        case .mixed:
            graph = mixedGraph(size: self.size, latencyNanos: latencyNanos)
        }

        let containerMap = Dictionary(uniqueKeysWithValues: graph.containers.map { ($0.package, $0) })
        let provider = BenchProvider(containers: containerMap, latencyNanos: latencyNanos)

        if !self.quiet {
            FileHandle.standardError.write(Data("topology=\(self.topology.rawValue) size=\(self.size) latency_ms=\(self.latencyMs) containers=\(graph.containers.count) iterations=\(self.iterations)\n".utf8))
        }

        for _ in 0 ..< self.iterations {
            let resolver = PubGrubDependencyResolver(
                provider: provider,
                observabilityScope: ObservabilitySystem.NOOP
            )
            let start = Date()
            let result = await resolver.solve(constraints: graph.rootConstraints)
            let elapsedMs = -start.timeIntervalSinceNow * 1000

            switch result {
            case .success(let bindings):
                if !self.quiet {
                    FileHandle.standardError.write(Data("ok bindings=\(bindings.count) elapsed_ms=\(String(format: "%.3f", elapsedMs))\n".utf8))
                }
                print(String(format: "%.3f", elapsedMs))
            case .failure(let error):
                throw BenchError.resolutionFailed(String(describing: error))
            }
        }
    }
}
