//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Dispatch
import PackageLoading
import PackageModel

import struct TSCUtility.Version

/// TODO: This could be removed once logic to handle provided libraries is integrated
/// into a \c PubGrubPackageContainer.
public struct ProvidedLibraryPackageContainer: PackageContainer {
    public let package: PackageReference

    /// Observability scope to emit diagnostics
    private let observabilityScope: ObservabilityScope

    public init(
        package: PackageReference,
        observabilityScope: ObservabilityScope
    ) throws {
        switch package.kind {
        case .providedLibrary:
            break
        default:
            throw InternalError("invalid package type \(package.kind)")
        }
        self.package = package
        self.observabilityScope = observabilityScope.makeChildScope(
            description: "ProvidedLibraryPackageContainer",
            metadata: package.diagnosticsMetadata)
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        true
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        .v6_0
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        return try versionsDescending()
    }

    public func versionsAscending() throws -> [Version] {
        [] // TODO
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        []
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        []
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        []
    }

    public func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        package
    }
}
