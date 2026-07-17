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
import TSCUtility
import PackageGraph
import PackageModel
import PackageLoading

public struct ArchivePackageContainer: PackageContainer {
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
    private let manifest = AsyncThrowingValueMemoizer<Manifest>()

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
        case .archive:
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
            description: "ArchivePackageContainer",
            metadata: package.diagnosticsMetadata)
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

    public func getUnversionedDependencies(productFilter: PackageModel.ProductFilter, _ enabledTraits: PackageModel.EnabledTraits) async throws -> [PackageContainerConstraint] {
        // TODO: We may want dependencies here
        return []
    }

    public func loadPackageReference(at boundVersion: BoundVersion) async throws -> PackageReference {
        return package
    }

    public func loadPackageTraits(at boundVersion: BoundVersion) async throws -> Set<TraitDescription> {
        // TODO: We may want traits at least for source archives
        return []
    }
}
