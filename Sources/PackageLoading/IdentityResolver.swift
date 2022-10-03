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

import Foundation
import PackageModel
import TSCBasic

// TODO: refactor this when adding registry support
public protocol IdentityResolver {
    // deprecated 9/21
    @available(*, deprecated, message: "use resolveIdentity for url or path instead")
    func resolveIdentity(for location: String) -> PackageIdentity
    func resolveIdentity(for packageKind: PackageReference.Kind) throws -> PackageIdentity
    func resolveIdentity(for url: URL) throws -> PackageIdentity
    func resolveIdentity(for path: AbsolutePath) throws -> PackageIdentity
    func mappedLocation(for location: String) -> String
}

public struct DefaultIdentityResolver: IdentityResolver {
    let locationMapper: (String) -> String

    public init(locationMapper: @escaping (String) -> String = { $0 }) {
        self.locationMapper = locationMapper
    }

    // deprecated 9/21
    @available(*, deprecated, message: "use resolveIdentity for url or path instead")
    public func resolveIdentity(for location: String) -> PackageIdentity {
        let location = self.mappedLocation(for: location)
        return PackageIdentity(urlString: location)
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

    public func resolveIdentity(for url: URL) throws -> PackageIdentity {
        let location = self.mappedLocation(for: url.absoluteString)
        if let path = try? AbsolutePath(validating: location) {
            return PackageIdentity(path: path)
        } else if let url = URL(string: location) {
            return PackageIdentity(url: url)
        } else {
            throw StringError("invalid mapped location: \(location) for \(url)")
        }
    }

    public func resolveIdentity(for path: AbsolutePath) throws -> PackageIdentity {
        let location = self.mappedLocation(for: path.pathString)
        if let path = try? AbsolutePath(validating: location) {
            return PackageIdentity(path: path)
        } else if let url = URL(string: location) {
            return PackageIdentity(url: url)
        } else {
            throw StringError("invalid mapped location: \(location) for \(path)")
        }
    }

    public func mappedLocation(for location: String) -> String {
        return self.locationMapper(location)
    }
}
