//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import _Concurrency
import Dispatch
import PackageGraph
import PackageLoading
import PackageModel

import struct TSCUtility.Version

/// Local file system package container.
///
/// This class represent packages that are referenced locally in the file system.
/// There is no need to perform any git operations on such packages and they
/// should be used as-is. In fact, they might not even have a git repository.
/// Examples: Root packages, local dependencies, edited packages.
public struct FileSystemPackageContainer: PackageContainer {
    public let package: PackageReference
    private let identityResolver: IdentityResolver
    private let dependencyMapper: DependencyMapper
    private let manifestLoader: ManifestLoaderProtocol
    private let currentToolsVersion: ToolsVersion

    /// The enclosing `Workspace.swift` manifest, when this container is
    /// resolving a workspace member. Populated by `PackageWorkspace` at
    /// container-construction time; when non-nil, the container applies
    /// `PackageWorkspace.resolveWorkspaceMemberPaths` on manifests it
    /// loads so that `.workspaceMember` / `.workspaceInherited` deps
    /// are rewritten before they reach downstream consumers.
    private let workspaceManifest: WorkspaceManifest?

    /// The parsed workspace overrides, when this container is resolving
    /// a workspace member. Populated by `PackageWorkspace` at
    /// container-construction time; when non-nil and non-empty, the
    /// container applies `WorkspaceOverridesJSONParser.apply(_:to:)` on
    /// manifests it loads so that member-declared dependencies matching
    /// an override are rewritten before they reach the resolver.
    private let overrides: [WorkspaceOverridesJSONParser.Override]?

    /// File system that should be used to load this package.
    private let fileSystem: FileSystem

    /// Observability scope to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// cached version of the manifest
    private let manifest = AsyncThrowingValueMemoizer<Manifest>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        workspaceManifest: WorkspaceManifest? = nil,
        overrides: [WorkspaceOverridesJSONParser.Override]? = nil,
    ) throws {
        switch package.kind {
        case .root, .fileSystem:
            break
        default:
            throw InternalError("invalid package type \(package.kind)")
        }
        self.package = package
        self.identityResolver = identityResolver
        self.dependencyMapper = dependencyMapper
        self.manifestLoader = manifestLoader
        self.currentToolsVersion = currentToolsVersion
        self.workspaceManifest = workspaceManifest
        self.overrides = overrides
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "FileSystemPackageContainer",
            metadata: package.diagnosticsMetadata)
    }

    package func loadManifest() async throws -> Manifest {
        try await manifest.memoize {
            let packagePath: AbsolutePath
            switch self.package.kind {
            case .root(let path), .fileSystem(let path):
                packagePath = path
            default:
                throw InternalError("invalid package type \(package.kind)")
            }

            // Load the manifest.
            let raw = try await manifestLoader.load(
                packagePath: packagePath,
                packageIdentity: self.package.identity,
                packageKind: self.package.kind,
                packageLocation: self.package.locationString,
                packageVersion: nil,
                currentToolsVersion: self.currentToolsVersion,
                identityResolver: self.identityResolver,
                dependencyMapper: self.dependencyMapper,
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope,
                delegateQueue: .sharedConcurrent
            )

            // Apply workspace-scoped dependency rewriting when this
            // container is resolving a workspace member. The pass is
            // idempotent for concrete dep kinds, so it's safe to run
            // even for containers whose manifests happen to have no
            // workspace-scoped deps.
            let processed: Manifest
            if let workspaceManifest {
                processed = try PackageWorkspace.resolveWorkspaceMemberPaths(
                    in: raw,
                    using: workspaceManifest,
                )
            } else {
                processed = raw
            }

            // Apply member-level overrides when this container is
            // resolving a workspace member and overrides are present.
            // This ensures that member-declared dependencies matching
            // an override are rewritten before the resolver attempts
            // to fetch them.
            let overridden: Manifest
            if let overrides, !overrides.isEmpty {
                overridden = WorkspaceOverridesJSONParser.apply(overrides, to: processed)
            } else {
                overridden = processed
            }
            return overridden
        }
    }

    public func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) async throws -> [PackageContainerConstraint] {
        let manifest = try await self.loadManifest()
        return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
    }

    public func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try await loadManifest()
        return package.withName(manifest.displayName)
    }

    public func loadPackageTraits(at boundVersion: BoundVersion) async throws -> Set<TraitDescription> {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try await loadManifest()
        return manifest.traits
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        fatalError("This should never be called")
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        fatalError("This should never be called")
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        fatalError("This should never be called")
    }

    public func versionsAscending() throws -> [Version] {
        fatalError("This should never be called")
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: EnabledTraits = ["default"]) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }
}

extension FileSystemPackageContainer: CustomStringConvertible  {
    public var description: String {
        return "FileSystemPackageContainer(\(self.package.identity))"
    }
}
