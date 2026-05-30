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

/// Configuration controlling whether and how a playground runner product is
/// synthesized for a package. A `nil` value of `PlaygroundProductConfiguration?`
/// opts the package out of playground product synthesis entirely.
public struct PlaygroundProductConfiguration: Equatable, Sendable {
    /// If non-nil, the synthesized playground runner is built with the named
    /// target as its sole declared playground link dependency, replacing the
    /// default rule of "library targets named in any product". The target's
    /// transitive dependencies are still linked normally.
    public let targetOverride: String?

    public init(targetOverride: String? = nil) {
        self.targetOverride = targetOverride
    }
}
