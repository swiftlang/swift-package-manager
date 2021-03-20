/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCUtility

public enum Sandbox {
    public static func apply(
        command: [String],
        writableDirectories: [AbsolutePath] = [],
        strictness: Strictness = .default
    ) -> [String] {
        #if os(macOS)
        let profile = macOSSandboxProfile(writableDirectories: writableDirectories, strictness: strictness)
        return ["/usr/bin/sandbox-exec", "-p", profile] + command
        #else
        // rdar://40235432, rdar://75636874 tracks implementing sandboxes for other platforms.
        return command
        #endif
    }

    public enum Strictness: Equatable {
        case `default`
        case manifest_pre_53 // backwards compatibility for manifests
    }
}

// MARK: - macOS

#if os(macOS)
fileprivate func macOSSandboxProfile(
    writableDirectories: [AbsolutePath],
    strictness: Sandbox.Strictness
) -> String {
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
    var writableDirectoriesExpression = writableDirectories.map {
        "(subpath \"\(resolveSymlinks($0).pathString)\")"
    }
    // The following accesses are only needed when interpreting the manifest (versus running a compiled version).
    if strictness == .manifest_pre_53 {
        writableDirectoriesExpression += Platform.threadSafeDarwinCacheDirectories.get().map {
            ##"(regex #"^\##($0.pathString)/org\.llvm\.clang.*")"##
        }
    }

    if writableDirectoriesExpression.count > 0 {
        contents += "(allow file-write*\n"
        for expression in writableDirectoriesExpression {
            contents += "    \(expression)\n"
        }
        contents += ")\n"
    }

    return contents
}

extension TSCUtility.Platform {
    fileprivate static let threadSafeDarwinCacheDirectories = ThreadSafeArrayStore<AbsolutePath>(Self.darwinCacheDirectories())
}
#endif
