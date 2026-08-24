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

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#elseif canImport(Android)
import Android
#elseif canImport(Darwin)
import Darwin.C
#elseif canImport(ucrt)
import ucrt
#elseif canImport(WASILibc)
import WASILibc
#endif

/// The declarative specification of a Swift workspace grouping multiple packages.
///
/// A workspace is declared in a `Workspace.swift` manifest at the root of a
/// directory that contains one or more Swift packages (its "members"). Each
/// member is an ordinary SwiftPM package with its own `Package.swift`.
/// Under a workspace, SwiftPM commands like `swift build`, `swift test`,
/// and `swift package resolve` operate across all members with unified
/// dependency resolution and shared build state.
@available(_PackageDescription, introduced: 999.0)
public struct Workspace {
    /// The member packages of the workspace, in declaration order.
    public let members: [Member]

    /// Workspace-wide dependencies that members may inherit via
    /// `.package(workspaceInherited:)`.
    public let dependencies: [Package.Dependency]

    /// Creates a workspace grouping the given member packages.
    ///
    /// - Parameters:
    ///   - members: The workspace's member package paths. Each may be a
    ///     bare string literal (defaulting to no state-directory
    ///     suppressions) or a call to ``member(path:ignoredStateDirectories:)``.
    ///   - dependencies: Workspace-wide dependencies that members inherit
    ///     via `.package(workspaceInherited:)`. Defaults to no shared
    ///     dependencies.
    public init(
        members: [Member],
        dependencies: [Package.Dependency] = [],
    ) {
        self.members = members
        self.dependencies = dependencies

        // Register an atexit handler so the manifest evaluator can read the
        // workspace's serialized form via the file descriptor passed on the
        // command line. Mirrors PackageDescription.Package's dump mechanism.
        #if os(Windows)
        if let index = CommandLine.arguments.firstIndex(of: "-handle") {
            if let handle = Int(CommandLine.arguments[index + 1], radix: 16) {
                dumpWorkspaceAtExit(self, to: handle)
            }
        }
        #else
        if let optIdx = CommandLine.arguments.firstIndex(of: "-fileno") {
            if let jsonOutputFileDesc = Int32(CommandLine.arguments[optIdx + 1]) {
                dumpWorkspaceAtExit(self, to: jsonOutputFileDesc)
            }
        }
        #endif
    }
}

@available(_PackageDescription, introduced: 999.0)
extension Workspace {
    /// A single member package of a workspace.
    public struct Member: Sendable, ExpressibleByStringLiteral {
        /// The path of the member relative to the workspace root.
        public let path: String

        /// State-directory kinds whose presence at the member level should
        /// be silently ignored (not surfaced in the trailing warning).
        public let ignoredStateDirectories: Set<StateDirectoryKind>

        /// Creates a member from a string literal path with no
        /// state-directory suppressions.
        public init(stringLiteral value: String) {
            self.path = value
            self.ignoredStateDirectories = []
        }

        /// Creates a member with the given path and state-directory
        /// suppressions.
        public init(
            path: String,
            ignoredStateDirectories: Set<StateDirectoryKind> = [],
        ) {
            self.path = path
            self.ignoredStateDirectories = ignoredStateDirectories
        }
    }

    /// Creates a workspace member with the given path and state-directory
    /// suppressions.
    ///
    /// Use this factory when the string-literal shorthand is not sufficient,
    /// for example when suppressing warnings for member-level state
    /// directories that are legitimately present.
    public static func member(
        path: String,
        ignoredStateDirectories: Set<StateDirectoryKind> = [],
    ) -> Member {
        Member(path: path, ignoredStateDirectories: ignoredStateDirectories)
    }

    /// Kinds of member-level state directories that a workspace may
    /// ignore when detecting stale state.
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

// MARK: - Serialization dispatch

#if os(Windows)
private var workspaceDumpInfo: (workspace: Workspace, handle: Int)?
private func dumpWorkspaceAtExit(_ workspace: Workspace, to handle: Int) {
    let dump: @convention(c) () -> Void = {
        guard let workspaceDumpInfo else { return }

        let hFile: HANDLE = HANDLE(bitPattern: workspaceDumpInfo.handle)!
        let fd: CInt = _open_osfhandle(Int(bitPattern: hFile), _O_APPEND)
        guard let fp = _fdopen(fd, "w") else {
            _close(fd)
            return
        }
        defer { fclose(fp) }
        fputs(workspaceManifestToJSON(workspaceDumpInfo.workspace), fp)
    }
    workspaceDumpInfo = (workspace, handle)
    atexit(dump)
}
#else
private var workspaceDumpInfo: (workspace: Workspace, fileDesc: Int32)?
private func dumpWorkspaceAtExit(_ workspace: Workspace, to fileDesc: Int32) {
    func dump() {
        guard let workspaceDumpInfo else { return }
        guard let fd = fdopen(workspaceDumpInfo.fileDesc, "w") else { return }
        fputs(workspaceManifestToJSON(workspaceDumpInfo.workspace), fd)
        fclose(fd)
    }
    workspaceDumpInfo = (workspace, fileDesc)
    atexit(dump)
}
#endif
