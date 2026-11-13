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
import PackageModel

import struct TSCUtility.Version

/// A resolved dependency to audit.
public struct AuditedPackage: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case sourceControl(url: String)
        case registry(identity: PackageIdentity, registryURL: URL?)
        case local(path: AbsolutePath)
    }

    public enum State: Sendable, Equatable {
        case version(Version)
        case revision(String)
        case none
    }

    public let identity: PackageIdentity
    public let kind: Kind
    public let state: State
    /// Repository URLs known for a registry package (from release metadata).
    public let repositoryURLs: [String]
    /// Dependency paths from the root package, each starting at a root dependency.
    public let paths: [[String]]

    public init(
        identity: PackageIdentity,
        kind: Kind,
        state: State,
        repositoryURLs: [String] = [],
        paths: [[String]] = []
    ) {
        self.identity = identity
        self.kind = kind
        self.state = state
        self.repositoryURLs = repositoryURLs
        self.paths = paths
    }
}
