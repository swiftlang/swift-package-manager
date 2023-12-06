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

import class Foundation.ProcessInfo

public typealias EnvironmentVariables = [String: String]

extension EnvironmentVariables {
    public static func empty() -> EnvironmentVariables {
        [:]
    }

    public static func process() -> EnvironmentVariables {
        ProcessInfo.processInfo.environment
    }

    public mutating func prependPath(_ key: String, value: String) {
        var values = value.isEmpty ? [] : [value]
        if let existing = self[key], !existing.isEmpty {
            values.append(existing)
        }
        self.setPath(key, values)
    }

    public mutating func appendPath(_ key: String, value: String) {
        var values = value.isEmpty ? [] : [value]
        if let existing = self[key], !existing.isEmpty {
            values.insert(existing, at: 0)
        }
        self.setPath(key, values)
    }

    private mutating func setPath(_ key: String, _ values: [String]) {
        #if os(Windows)
        let delimiter = ";"
        #else
        let delimiter = ":"
        #endif
        self[key] = values.joined(separator: delimiter)
    }

    /// `PATH` variable in the process's environment (`Path` under Windows).
    public var path: String? {
        #if os(Windows)
        let pathArg = "Path"
        #else
        let pathArg = "PATH"
        #endif
        return self[pathArg]
    }
}

// filter env variable that should not be included in a cache as they change
// often and should not be considered in business logic
// rdar://107029374
extension EnvironmentVariables {
    // internal for testing
    internal static let nonCachableKeys: Set<String> = [
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
    ]

    public var cachable: EnvironmentVariables {
        return self.filter { !Self.nonCachableKeys.contains($0.key) }
    }
}
