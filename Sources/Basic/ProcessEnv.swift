/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import SPMLibc
import enum POSIX.SystemError

/// Provides functionality related a process's enviorment.
public enum ProcessEnv {

    /// Returns a dictionary containing the current environment.
    public static var vars: [String: String] {
        return ProcessInfo.processInfo.environment
    }

    /// Set the given key and value in the process's environment.
    public static func setVar(_ key: String, value: String) throws {
        // FIXME: Need to handle Windows.
        guard SPMLibc.setenv(key, value, 1) == 0 else {
            throw SystemError.setenv(errno, key)
        }
    }

    /// Unset the give key in the process's environment.
    public static func unsetVar(_ key: String) throws {
        // FIXME: Need to handle Windows.
        guard SPMLibc.unsetenv(key) == 0 else {
            throw SystemError.unsetenv(errno, key)
        }
    }

    /// The current working directory of the process.
    public static var cwd: AbsolutePath? {
        return localFileSystem.currentWorkingDirectory
    }

    /// Change the current working directory of the process.
    public static func chdir(_ path: AbsolutePath) throws {
        // FIXME: Need to handle Windows.
        let path = path.pathString
        guard SPMLibc.chdir(path) == 0 else {
            throw SystemError.chdir(errno, path)
        }
    }
}
