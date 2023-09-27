//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

// TODO: refactor this when adding registry support
public protocol IdentityResolver {
    func resolveIdentity(for packageKind: PackageReference.Kind) throws -> PackageIdentity
    func resolveIdentity(for url: SourceControlURL) throws -> PackageIdentity
    func resolveIdentity(for path: AbsolutePath) throws -> PackageIdentity
    func mappedLocation(for location: String) -> String
    func mappedIdentity(for identity: PackageIdentity) throws -> PackageIdentity
}

public struct DefaultIdentityResolver: IdentityResolver {
    let locationMapper: (String) -> String
    let identityMapper: (PackageIdentity) throws -> PackageIdentity

    public init(
        locationMapper: @escaping (String) -> String = { $0 },
        identityMapper: @escaping (PackageIdentity) throws -> PackageIdentity = { $0 }
    ) {
        self.locationMapper = locationMapper
        self.identityMapper = identityMapper
    }

    public func resolveIdentity(for packageKind: PackageReference.Kind) throws -> PackageIdentity {
        switch packageKind {
        case .root(let path):
            return try self.resolveIdentity(for: path)
        case .fileSystem(let path):
            return try self.resolveIdentity(for: path)
        case .localSourceControl(let path):
            return try self.resolveIdentity(for: path)
        case .remoteSourceControl(let url):
            return try self.resolveIdentity(for: url)
        case .registry(let identity):
            return identity
        }
    }

    public func resolveIdentity(for url: SourceControlURL) throws -> PackageIdentity {
        let location = self.mappedLocation(for: url.absoluteString)
        if let path = try? AbsolutePath(validating: location) {
            return PackageIdentity(path: path)
        } else {
            return PackageIdentity(url: SourceControlURL(location))
        }
    }

    public func resolveIdentity(for path: AbsolutePath) throws -> PackageIdentity {
        let location = self.mappedLocation(for: path.pathString)
        if let path = try? AbsolutePath(validating: location) {
            return PackageIdentity(path: path)
        } else {
            return PackageIdentity(url: SourceControlURL(location))
        }
    }

    public func mappedLocation(for location: String) -> String {
        self.locationMapper(location)
    }

    public func mappedIdentity(for identity: PackageIdentity) throws -> PackageIdentity {
        try self.identityMapper(identity)
    }
}
