//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import PackageModel
import struct TSCUtility.Version

/// A package container that can represent a prebuilt library from a package.
public struct PrebuiltPackageContainer: PackageContainer {
    private let chosenIdentity: LibraryMetadata.Identity
    private let metadata: LibraryMetadata

    public init(metadata: LibraryMetadata) throws {
        self.metadata = metadata

        // FIXME: Unclear what is supposed to happen if we have multiple identities.
        if let identity = metadata.identities.first {
            self.chosenIdentity = identity
        } else {
            let name = metadata.productName.map { "'\($0)' " } ?? ""
            throw InternalError("provided library \(name)does not specifiy any identities")
        }
    }

    public var package: PackageReference {
        return .init(identity: chosenIdentity.identity, kind: chosenIdentity.kind)
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        return true
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        return .v4
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        return try versionsAscending()
    }

    public func versionsAscending() throws -> [Version] {
        return [.init(stringLiteral: metadata.version)]
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return []
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return []
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        return []
    }

    public func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        return package
    }
}
