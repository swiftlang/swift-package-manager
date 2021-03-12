/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel

// TODO: refactor this when adding registry support
public protocol IdentityResolver {
    func resolveIdentity(for location: String) -> PackageIdentity
    func resolveIdentity(for path: AbsolutePath) -> PackageIdentity
    func resolveLocation(from location: String) -> String
}

public struct DefaultIdentityResolver: IdentityResolver {
    let locationMapper: (String) -> String

    public init(locationMapper: @escaping (String) -> String = { $0 }) {
        self.locationMapper = locationMapper
    }
    
    public func resolveIdentity(for location: String) -> PackageIdentity {
        let location = self.resolveLocation(from: location)
        return PackageIdentity(url: location)
    }

    public func resolveIdentity(for path: AbsolutePath) -> PackageIdentity {
        return PackageIdentity(url: path.pathString)
    }

    public func resolveLocation(from location: String) -> String {
        return self.locationMapper(location)
    }
}
