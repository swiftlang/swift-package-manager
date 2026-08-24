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

/// The declarative specification loaded from a `Workspace.swift` manifest.
///
/// A workspace groups multiple Swift packages ("members") for unified
/// dependency resolution and shared build state. Members are ordinary
/// SwiftPM packages, each with their own `Package.swift`.
public struct WorkspaceManifest: Sendable {
    /// The standard filename for the workspace manifest.
    public static let filename = "Workspace.swift"

    /// The path of the `Workspace.swift` manifest file.
    public let path: AbsolutePath

    /// The Swift tools version declared in the manifest header.
    public let toolsVersion: ToolsVersion

    /// The workspace's declared member packages.
    public let members: [Member]

    /// Workspace-wide dependencies that members may inherit via
    /// `.package(workspaceInherited:)`.
    public let dependencies: [PackageDependency]

    public init(
        path: AbsolutePath,
        toolsVersion: ToolsVersion,
        members: [Member],
        dependencies: [PackageDependency],
    ) {
        self.path = path
        self.toolsVersion = toolsVersion
        self.members = members
        self.dependencies = dependencies
    }
}

extension WorkspaceManifest {
    /// A single member package of a workspace.
    public struct Member: Sendable {
        /// The canonical identity of the member, derived from its path.
        public let identity: PackageIdentity

        /// The absolute filesystem path of the member's package root.
        public let path: AbsolutePath

        /// State directory kinds whose presence at the member level should
        /// be silently ignored (not surfaced in the trailing warning).
        public let ignoredStateDirectories: Set<StateDirectoryKind>

        public init(
            identity: PackageIdentity,
            path: AbsolutePath,
            ignoredStateDirectories: Set<StateDirectoryKind> = [],
        ) {
            self.identity = identity
            self.path = path
            self.ignoredStateDirectories = ignoredStateDirectories
        }
    }

    /// Kinds of member-level state directories that a workspace may
    /// ignore when detecting stale state files.
    public enum StateDirectoryKind: Sendable, Hashable {
        /// `.build/`
        case build
        /// `Package.resolved`
        case packageResolved
        /// `Packages/`
        case packages
        /// `.swiftpm/configuration/`
        case swiftpmConfig
    }
}
