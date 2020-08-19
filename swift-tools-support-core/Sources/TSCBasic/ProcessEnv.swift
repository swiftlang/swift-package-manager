/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCLibc

/// Provides functionality related a process's enviorment.
public enum ProcessEnv {

    /// Returns a dictionary containing the current environment.
    public static var vars: [String: String] { _vars }
    private static var _vars = ProcessInfo.processInfo.environment

    /// Invalidate the cached env.
    public static func invalidateEnv() {
        _vars = ProcessInfo.processInfo.environment
    }

    /// Set the given key and value in the process's environment.
    public static func setVar(_ key: String, value: String) throws {
      #if os(Windows)
        guard key.withCString(encodedAs: UTF16.self, { keyStr in
            value.withCString(encodedAs: UTF16.self) { valStr in
                SetEnvironmentVariableW(keyStr, valStr)
            }
        }) else {
            throw SystemError.setenv(Int32(GetLastError()), key)
        }
      #else
        guard TSCLibc.setenv(key, value, 1) == 0 else {
            throw SystemError.setenv(errno, key)
        }
      #endif
        invalidateEnv()
    }

    /// Unset the give key in the process's environment.
    public static func unsetVar(_ key: String) throws {
      #if os(Windows)
        guard key.withCString(encodedAs: UTF16.self, { keyStr in
            SetEnvironmentVariableW(keyStr, nil)
        }) else {
            throw SystemError.unsetenv(Int32(GetLastError()), key)
        }
      #else
        guard TSCLibc.unsetenv(key) == 0 else {
            throw SystemError.unsetenv(errno, key)
        }
      #endif
        invalidateEnv()
    }

    /// `PATH` variable in the process's environment (`Path` under Windows).
    public static var path: String? {
#if os(Windows)
        let pathArg = "Path"
#else
        let pathArg = "PATH"
#endif
        return vars[pathArg]
    }

    /// The current working directory of the process.
    public static var cwd: AbsolutePath? {
        return localFileSystem.currentWorkingDirectory
    }

    /// Change the current working directory of the process.
    public static func chdir(_ path: AbsolutePath) throws {
        let path = path.pathString
      #if os(Windows)
        guard path.withCString(encodedAs: UTF16.self, {
            SetCurrentDirectoryW($0)
        }) else {
            throw SystemError.chdir(Int32(GetLastError()), path)
        }
      #else
        guard TSCLibc.chdir(path) == 0 else {
            throw SystemError.chdir(errno, path)
        }
      #endif
    }
}
