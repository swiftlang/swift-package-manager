//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import TSCBasic

import enum TSCUtility.Platform

public enum Sandbox {

    /// Applies a sandbox invocation to the given command line (if the platform supports it),
    /// and returns the modified command line. On platforms that don't support sandboxing, the
    /// command line is returned unmodified.
    ///
    /// - Parameters:
    ///   - command: The command line to sandbox (including executable as first argument)
    ///   - strictness: The basic strictness level of the standbox.
    ///   - writableDirectories: Paths under which writing should be allowed, even if they would otherwise be read-only based on the strictness or paths in `readOnlyDirectories`.
    ///   - readOnlyDirectories: Paths under which writing should be denied, even if they would have otherwise been allowed by the rules implied by the strictness level.
    public static func apply(
        command: [String],
        strictness: Strictness = .default,
        writableDirectories: [AbsolutePath] = [],
        readOnlyDirectories: [AbsolutePath] = []
    ) throws -> [String] {
        #if os(macOS)
        let profile = try macOSSandboxProfile(strictness: strictness, writableDirectories: writableDirectories, readOnlyDirectories: readOnlyDirectories)
        return ["/usr/bin/sandbox-exec", "-p", profile] + command
        #else
        // rdar://40235432, rdar://75636874 tracks implementing sandboxes for other platforms.
        return command
        #endif
    }

    /// Basic strictness level of a sandbox applied to a command line.
    public enum Strictness: Equatable {
        /// Blocks network access and all file system modifications.
        case `default`
        /// More lenient restrictions than the default, for compatibility with SwiftPM manifests using a tools version older than 5.3.
        case manifest_pre_53 // backwards compatibility for manifests
        /// Like `default`, but also makes temporary-files directories (such as `/tmp`) on the platform writable.
        case writableTemporaryDirectory
    }
}

// MARK: - macOS

#if os(macOS)
fileprivate func macOSSandboxProfile(
    strictness: Sandbox.Strictness,
    writableDirectories: [AbsolutePath],
    readOnlyDirectories: [AbsolutePath]
) throws -> String {
    var contents = "(version 1)\n"

    // Deny everything by default.
    contents += "(deny default)\n"

    // Import the system sandbox profile.
    contents += "(import \"system.sb\")\n"

    // Allow reading all files; ideally we'd only allow the package directory and any dependencies,
    // but all kinds of system locations need to be accessible.
    contents += "(allow file-read*)\n"

    // This is needed to launch any processes.
    contents += "(allow process*)\n"

    // The following accesses are only needed when interpreting the manifest (versus running a compiled version).
    if strictness == .manifest_pre_53 {
        // This is required by the Swift compiler.
        contents += "(allow sysctl*)\n"
    }

    // Allow writing only to certain directories.
    var writableDirectoriesExpression: [String] = []

    // The following accesses are only needed when interpreting the manifest (versus running a compiled version).
    if strictness == .manifest_pre_53 {
        writableDirectoriesExpression += Platform.threadSafeDarwinCacheDirectories.get().map {
            ##"(regex #"^\##($0.pathString)/org\.llvm\.clang.*")"##
        }
    }
    // Optionally allow writing to temporary directories (a lot of use of Foundation requires this).
    else if strictness == .writableTemporaryDirectory {
        // Add `subpath` expressions for the regular and the Foundation temporary directories.
        for tmpDir in ["/tmp", NSTemporaryDirectory()] {
            writableDirectoriesExpression += try ["(subpath \(resolveSymlinks(AbsolutePath(validating: tmpDir)).quotedAsSubpathForSandboxProfile))"]
        }
    }

    // Emit rules for paths under which writing is allowed. Some of these expressions may be regular expressions and others literal subpaths.
    if writableDirectoriesExpression.count > 0 {
        contents += "(allow file-write*\n"
        for expression in writableDirectoriesExpression {
            contents += "    \(expression)\n"
        }
        contents += ")\n"
    }

    // Emit rules for paths under which writing should be disallowed, even if they would be covered by a previous rule to allow writing to them. A classic case is a package which is located under the temporary directory, which should be read-only even though the temporary directory as a whole is writable.
    if readOnlyDirectories.count > 0 {
        contents += "(deny file-write*\n"
        for path in readOnlyDirectories {
            contents += "    (subpath \(try resolveSymlinks(path).quotedAsSubpathForSandboxProfile))\n"
        }
        contents += ")\n"
    }

    // Emit rules for paths under which writing is allowed, even if they are descendants directories that are otherwise read-only.
    if writableDirectories.count > 0 {
        contents += "(allow file-write*\n"
        for path in writableDirectories {
            contents += "    (subpath \(try resolveSymlinks(path).quotedAsSubpathForSandboxProfile))\n"
        }
        contents += ")\n"
    }

    return contents
}

fileprivate extension AbsolutePath {
    /// Private computed property that returns a version of the path as a string quoted for use as a subpath in a .sb sandbox profile.
    var quotedAsSubpathForSandboxProfile: String {
        return "\"" + self.pathString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}

extension TSCUtility.Platform {
    fileprivate static let threadSafeDarwinCacheDirectories = ThreadSafeArrayStore<AbsolutePath>((try? Self.darwinCacheDirectories()) ?? [])
}
#endif
