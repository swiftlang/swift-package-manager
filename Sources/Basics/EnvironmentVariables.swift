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
import class Foundation.ProcessInfo
import struct TSCBasic.ProcessEnvironmentBlock
import struct TSCBasic.ProcessEnvironmentKey
import enum TSCBasic.ProcessEnv

public typealias ProcessEnvironmentBlock = TSCBasic.ProcessEnvironmentBlock

extension ProcessEnvironmentBlock {
    public static var current: ProcessEnvironmentBlock { ProcessEnv.block }

    public mutating func prependPath(value: String) {
        if let existing = self[Self.pathKey] {
            self[Self.pathKey] = "\(value):\(existing)"
        } else {
            self[Self.pathKey] = value
        }
    }

    public mutating func appendPath(value: String) {
        if let existing = self[Self.pathKey] {
            self[Self.pathKey] = "\(existing):\(value)"
        } else {
            self[Self.pathKey] = value
        }
    }

    /// `PATH` variable in the process's environment (`Path` under Windows).
    package var path: String? { self[Self.pathKey] }

    package static var pathValueDelimiter: String {
        #if os(Windows)
        ";"
        #else
        ":"
        #endif
    }

    package static var pathKey: ProcessEnvironmentKey {
        #if os(Windows)
        "Path"
        #else
        "PATH"
        #endif
    }
}

// filter env variable that should not be included in a cache as they change
// often and should not be considered in business logic
// rdar://107029374
extension ProcessEnvironmentBlock {
    // internal for testing
    static let nonCachableKeys: Set<ProcessEnvironmentKey> = [
        "TERM",
        "TERM_PROGRAM",
        "TERM_PROGRAM_VERSION",
        "TERM_SESSION_ID",
        "ITERM_PROFILE",
        "ITERM_SESSION_ID",
        "SECURITYSESSIONID",
        "LaunchInstanceID",
        "LC_TERMINAL",
        "LC_TERMINAL_VERSION",
        "CLICOLOR",
        "LS_COLORS",
        "VSCODE_IPC_HOOK_CLI",
        "HYPERFINE_RANDOMIZED_ENVIRONMENT_OFFSET",
        "SSH_AUTH_SOCK",
    ]

    /// Returns a copy of `self` with known non-cacheable keys removed.
    public var cachable: ProcessEnvironmentBlock {
        self.filter { !Self.nonCachableKeys.contains($0.key) }
    }
}

extension ProcessEnvironmentKey: @retroactive Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        #if os(Windows)
        // TODO: is this any faster than just doing a lowercased conversion and compare?
        lhs.value.caseInsensitiveCompare(rhs.value) == .orderedAscending
        #else
        lhs.value < rhs.value
        #endif
    }
}

extension ProcessEnvironmentBlock {
    package func nonPortable() -> [String: String] {
        var dict = [String: String]()
        for (key, value) in self {
            dict[key.value] = value
        }
        return dict
    }
}
