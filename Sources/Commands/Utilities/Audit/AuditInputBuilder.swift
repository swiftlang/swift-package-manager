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
import PackageGraph
import PackageModel

/// Builds the list of packages to audit from a loaded package graph and `Package.resolved`.
enum AuditInputBuilder {
    /// Maximum number of dependency paths recorded per package.
    static let maxPathsPerPackage = 10

    static func makePackages(
        graph: ModulesGraph,
        resolvedPackages: ResolvedPackagesStore
    ) -> [AuditedPackage] {
        let pins = resolvedPackages.resolvedPackages
        let paths = self.dependencyPaths(graph: graph)

        var result: [AuditedPackage] = []

        let sortedPackages = graph.packages.sorted { $0.identity.description < $1.identity.description }
        for package in sortedPackages where !graph.isRootPackage(package) {
            let pin = pins[package.identity]
            let kind: PackageReference.Kind = pin?.packageRef.kind ?? package.manifest.packageKind
            guard let auditKind = self.auditKind(for: kind, package: package) else { continue }

            var repositoryURLs: [String] = []
            if case .registry = auditKind {
                repositoryURLs = package.registryMetadata?.metadata.scmRepositoryURLs?.map(\.absoluteString) ?? []
            }

            result.append(AuditedPackage(
                identity: package.identity,
                kind: auditKind,
                state: pin.map { self.state(for: $0.state, kind: auditKind) } ?? .none,
                repositoryURLs: repositoryURLs,
                paths: paths[package.identity] ?? []
            ))
        }

        // Pins that are no longer part of the graph are still audited, but have no known path.
        let graphIdentities = Set(graph.packages.map(\.identity))
        for (identity, pin) in pins.sorted(by: { $0.key.description < $1.key.description })
        where !graphIdentities.contains(identity) {
            guard let auditKind = self.auditKind(for: pin.packageRef.kind, package: nil) else { continue }
            result.append(AuditedPackage(
                identity: identity,
                kind: auditKind,
                state: self.state(for: pin.state, kind: auditKind),
                repositoryURLs: [],
                paths: []
            ))
        }

        return result
    }

    private static func auditKind(for kind: PackageReference.Kind, package: ResolvedPackage?) -> AuditedPackage.Kind? {
        switch kind {
        case .root:
            return nil
        case .fileSystem(let path):
            return .local(path: path)
        case .localSourceControl(let path):
            // `URL(fileURLWithPath:)` produces a valid file URL on every platform (e.g. `file:///C:/...` on Windows).
            return .sourceControl(url: URL(fileURLWithPath: path.pathString, isDirectory: false).absoluteString)
        case .remoteSourceControl(let url):
            return .sourceControl(url: url.absoluteString)
        case .registry(let identity):
            var registryURL: URL?
            if case .registry(let url)? = package?.registryMetadata?.source {
                registryURL = url
            }
            return .registry(identity: identity, registryURL: registryURL)
        }
    }

    private static func state(
        for state: ResolvedPackagesStore.ResolutionState,
        kind: AuditedPackage.Kind
    ) -> AuditedPackage.State {
        if case .local = kind { return .none }
        switch state {
        case .version(let version, _):
            return .version(version)
        case .branch(_, let revision), .revision(let revision):
            return .revision(revision)
        }
    }

    /// All simple paths from each root to every reachable package, capped per package.
    private static func dependencyPaths(graph: ModulesGraph) -> [PackageIdentity: [[String]]] {
        var result: [PackageIdentity: [[String]]] = [:]

        func walk(_ package: ResolvedPackage, trail: [ResolvedPackage]) {
            for identity in package.dependencies {
                guard let dependency = graph.package(for: identity),
                      !trail.contains(where: { $0.identity == identity })
                else { continue }

                // Once a package has the maximum number of paths, its descendants already have at least that many
                // (the graph is walked acyclically), so descending again would only re-do capped work.
                guard (result[identity]?.count ?? 0) < self.maxPathsPerPackage else { continue }
                let nextTrail = trail + [dependency]
                result[identity, default: []].append(nextTrail.map(\.manifest.displayName))
                walk(dependency, trail: nextTrail)
            }
        }

        for root in graph.rootPackages {
            walk(root, trail: [root])
        }
        return result
    }
}
