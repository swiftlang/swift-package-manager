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

import Foundation

public struct LibraryMetadata {
    public enum Identity: Equatable {
        case packageIdentity(scope: String, name: String)
        case sourceControl(url: URL)
    }

    /// The package from which it was built (e.g., the URL https://github.com/apple/swift-syntax.git)
    public let identities: [Identity]
    /// The version that was built (e.g., 509.0.2)
    public let version: String
    /// The product name, if it differs from the module name (e.g., SwiftParser).
    public let productName: String?

    let schemaVersion: Int
}

extension LibraryMetadata.Identity {
    public var identity: PackageIdentity {
        switch self {
        case .packageIdentity(let scope, let name):
            return PackageIdentity.plain("\(scope)/\(name)")
        case .sourceControl(let url):
            return PackageIdentity(url: .init(url))
        }
    }

    public var kind: PackageReference.Kind {
        switch self {
        case .packageIdentity:
            return .registry(self.identity)
        case .sourceControl(let url):
            return .remoteSourceControl(.init(url.absoluteString))
        }
    }

    public var ref: PackageReference {
        return PackageReference(identity: self.identity, kind: self.kind)
    }
}

// FIXME: Hard-coded metadata, this should be harvested from the used SDK.
public let AvailableLibraries: [LibraryMetadata] = [
    .init(
        identities: [
            .sourceControl(url: URL(string: "https://github.com/apple/swift-testing.git")!),
        ],
        version: "0.4.0",
        productName: "Testing",
        schemaVersion: 1
    )
]
