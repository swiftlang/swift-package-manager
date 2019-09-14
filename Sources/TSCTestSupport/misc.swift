/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func XCTest.XCTFail
import class Foundation.NSDate
import class Foundation.Thread

import TSCBasic
import TSCUtility

#if os(macOS)
import class Foundation.Bundle
#endif

public enum Configuration {
    case Debug
    case Release
}

/// Test helper utility for executing a block with a temporary directory.
public func mktmpdir(
    function: StaticString = #function,
    file: StaticString = #file,
    line: UInt = #line,
    body: (AbsolutePath) throws -> Void
) {
    do {
        let cleanedFunction = function.description
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
        try withTemporaryDirectory(prefix: "spm-tests-\(cleanedFunction)") { tmpDirPath in
            defer {
                // Unblock and remove the tmp dir on deinit.
                try? localFileSystem.chmod(.userWritable, path: tmpDirPath, options: [.recursive])
                try? localFileSystem.removeFileTree(tmpDirPath)
            }
            try body(tmpDirPath)
        }
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}

public func systemQuietly(_ args: [String]) throws {
    // Discard the output, by default.
    //
    // FIXME: Find a better default behavior here.
    try Process.checkNonZeroExit(arguments: args)
}

public func systemQuietly(_ args: String...) throws {
    try systemQuietly(args)
}

/// Temporary override environment variables
///
/// WARNING! This method is not thread-safe. POSIX environments are shared
/// between threads. This means that when this method is called simultaneously
/// from different threads, the environment will neither be setup nor restored
/// correctly.
public func withCustomEnv(_ env: [String: String], body: () throws -> Void) throws {
    let state = Array(env.keys).map({ ($0, ProcessEnv.vars[$0]) })
    let restore = {
        for (key, value) in state {
            if let value = value {
                try ProcessEnv.setVar(key, value: value)
            } else {
                try ProcessEnv.unsetVar(key)
            }
        }
    }
    do {
        for (key, value) in env {
            try ProcessEnv.setVar(key, value: value)
        }
        try body()
    } catch {
        try? restore()
        throw error
    }
    try restore()
}

/// Waits for a file to appear for around 1 second.
/// Returns true if found, false otherwise.
public func waitForFile(_ path: AbsolutePath) -> Bool {
    let endTime = NSDate().timeIntervalSince1970 + 2
    while NSDate().timeIntervalSince1970 < endTime {
        // Sleep for a bit so we don't burn a lot of CPU.
        Thread.sleep(forTimeInterval: 0.01)
        if localFileSystem.exists(path) {
            return true
        }
    }
    return false
}

extension Process {
    /// If the given pid is running or not.
    ///
    /// - Parameters:
    ///   - pid: The pid to check.
    ///   - orDefunct: If set to true, the method will also check if pid is defunct and return false.
    /// - Returns: True if the given pid is running.
    public static func running(_ pid: ProcessID, orDefunct: Bool = false) throws -> Bool {
        // Shell out to `ps -s` instead of using getpgid() as that is more deterministic on linux.
        let result = try Process.popen(arguments: ["ps", "-p", String(pid)])
        // If ps -p exited with return code 1, it means there is no entry for the process.
        var exited = result.exitStatus == .terminated(code: 1)
        if orDefunct {
            // Check if the process became defunct.
            exited = try exited || result.utf8Output().contains("defunct")
        }
        return !exited
    }
}
