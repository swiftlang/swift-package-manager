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

    /// File system that should be used to load this package.
    private let fileSystem: FileSystem

    /// Observability scope to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// cached version of the manifest
    private let manifest = ThreadSafeBox<Manifest>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        dependencyMapper: DependencyMapper,
        manifestLoader: ManifestLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
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
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "FileSystemPackageContainer",
            metadata: package.diagnosticsMetadata)
    }

    private func loadManifest() async throws -> Manifest {
        try await manifest.memoize() {
            let packagePath: AbsolutePath
            switch self.package.kind {
            case .root(let path), .fileSystem(let path):
                packagePath = path
            default:
                throw InternalError("invalid package type \(package.kind)")
            }

            // Load the manifest.
            // FIXME: this should not block
            return try await withCheckedThrowingContinuation { continuation in
                manifestLoader.load(
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
                    delegateQueue: .sharedConcurrent,
                    callbackQueue: .sharedConcurrent,
                    completion: {
                        continuation.resume(with: $0)
                    }
                )
            }
        }
    }

    public func getUnversionedDependencies(productFilter: ProductFilter, _ enabledTraits: Set<String>?) async throws -> [PackageContainerConstraint] {
        let manifest = try await self.loadManifest()
        return try manifest.dependencyConstraints(productFilter: productFilter, enabledTraits)
    }

    public func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try await loadManifest()
        return package.withName(manifest.displayName)
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

    public func getDependencies(at version: Version, productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter, _ enabledTraits: Set<String>?) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getEnabledTraits(traitConfiguration: TraitConfiguration?, at version: Version? = nil) async throws -> Set<String> {
        guard version == nil else {
            throw InternalError("File system package container does not support versioning.")
        }
        let manifest = try await loadManifest()
        guard manifest.packageKind.isRoot else {
            return []
        }
        let enabledTraits = try manifest.enabledTraits(using: traitConfiguration?.enabledTraits, enableAllTraits: traitConfiguration?.enableAllTraits ?? false)
        return enabledTraits ?? []
    }
}

extension FileSystemPackageContainer: CustomStringConvertible  {
    public var description: String {
        return "FileSystemPackageContainer(\(self.package.identity))"
    }
}
