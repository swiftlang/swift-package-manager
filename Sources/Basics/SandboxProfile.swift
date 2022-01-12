/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic

/// A sandbox profile representing the desired restrictions. The implementation can vary between platforms. Currently
/// the only control a client has is in the path rules, but in the future there should also be options for controlling
/// blocking of network access and process launching.
public struct SandboxProfile: Equatable {
    /// An ordered list of path rules, where the last rule to cover a particular path "wins". These will be resolved
    /// to absolute paths at the time the profile is applied. They are applied after any of the implicit directories
    /// referenced by other sandbox profile settings.
    public var pathAccessRules: [PathAccessRule]

    /// Represents a rule for access to a path and everything under it.
    public enum PathAccessRule: Equatable {
        case noaccess(AbsolutePath)
        case readonly(AbsolutePath)
        case writable(AbsolutePath)
    }

    /// Configures a SandboxProfile for blocking network access and writing to the file system except to specifically
    /// permitted locations.
    public init(_ pathAccessRules: [PathAccessRule] = []) {
        self.pathAccessRules = pathAccessRules
    }
}

extension SandboxProfile {
    /// Applies the sandbox profile to the given command line (if the platform supports it), and returns the modified
    /// command line. On platforms that don't support sandboxing, the unmodified command line is returned.
    public func apply(to command: [String]) throws -> [String] {
        #if os(macOS)
        return ["/usr/bin/sandbox-exec", "-p", try self.generateMacOSSandboxProfileString()] + command
        #else
        // rdar://40235432, rdar://75636874 tracks implementing sandboxes for other platforms.
        return command
        #endif
    }
}

// MARK: - macOS

#if os(macOS)
fileprivate extension SandboxProfile {
    /// Private function that generates a Darwin sandbox profile suitable for passing to `sandbox-exec(1)`.
    func generateMacOSSandboxProfileString() throws -> String {
        var contents = "(version 1)\n"

        // Deny everything by default.
        contents += "(deny default)\n"

        // Import the system sandbox profile.
        contents += "(import \"system.sb\")\n"

        // Allow operations on subprocesses.
        contents += "(allow process*)\n"

        // Allow reading any file that isn't protected by TCC or permissions (ideally we'd only allow a specific set
        // of readable locations, and can maybe tighten this in the future).
        contents += "(allow file-read*)\n"

        // Apply customized rules for specific file system locations. Everything is readonly by default, so we just
        // either allow or deny writing, in order. Later rules have precedence over earlier rules.
        for rule in pathAccessRules {
            switch rule {
            case .noaccess(let path):
                contents += "(deny file-* (subpath \(try resolveSymlinksAndQuotePath(path))))\n"
            case .readonly(let path):
                contents += "(deny file-write* (subpath \(try resolveSymlinksAndQuotePath(path))))\n"
            case .writable(let path):
                contents += "(allow file-write* (subpath \(try resolveSymlinksAndQuotePath(path))))\n"
            }
        }
        return contents
    }

    /// Private helper function that resolves an AbsolutePath and returns it as a string quoted for use as a subpath
    /// in a .sb sandbox profile.
    func resolveSymlinksAndQuotePath(_ path: AbsolutePath) throws -> String {
        return try "\"" + resolveSymlinks(path).pathString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
#endif
