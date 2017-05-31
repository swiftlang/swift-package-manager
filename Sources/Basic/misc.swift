/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import POSIX

/// Replace the current process image with a new process image.
///
/// - Parameters:
///   - path: Absolute path to the executable.
///   - args: The executable arguments.
public func exec(path: String, args: [String]) throws {
    let cArgs = CStringArray(args)
    guard execv(path, cArgs.cArray) != -1 else {
        throw POSIX.SystemError.exec(errno, path: path, args: args)
    }
}

// MARK: Utility function for searching for executables

/// Create a list of AbsolutePath search paths from a string, such as the PATH environment variable.
///
/// - Parameters:
///   - pathString: The path string to parse.
///   - currentWorkingDirectory: The current working directory, the relative paths will be converted to absolute paths
///     based on this path.
/// - Returns: List of search paths.
public func getEnvSearchPaths(
    pathString: String?,
    currentWorkingDirectory cwd: AbsolutePath
) -> [AbsolutePath] {
    // Compute search paths from PATH variable.
    return (pathString ?? "").characters.split(separator: ":").map(String.init).map({ pathString in
        // If this is an absolute path, we're done.
        if pathString.characters.first == "/" {
            return AbsolutePath(pathString)
        }
        // Otherwise convert it into absolute path relative to the working directory.
        return AbsolutePath(pathString, relativeTo: cwd)
    })
}

/// Lookup an executable path from an environment variable value, current working
/// directory or search paths. Only return a value that is both found and executable.
///
/// This method searches in the following order:
/// * If env value is a valid absolute path, return it.
/// * If env value is relative path, first try to locate it in current working directory.
/// * Otherwise, in provided search paths.
///
/// - Parameters:
///   - filename: The name of the file to find.
///   - cwd: The current working directory to look in.
///   - searchPaths: The additional search paths to look in if not found in cwd.
/// - Returns: Valid path to executable if present, otherwise nil.
public func lookupExecutablePath(
    filename value: String?,
    currentWorkingDirectory cwd: AbsolutePath = currentWorkingDirectory,
    searchPaths: [AbsolutePath] = []
) -> AbsolutePath? {
    // We should have a value to continue.
    guard let value = value, !value.isEmpty else {
        return nil
    }
    // We have a value, but it could be an absolute or a relative path.
    let path = AbsolutePath(value, relativeTo: cwd)
    if localFileSystem.isExecutableFile(path) {
        return path
    }
    // Ensure the value is not a path.
    guard !value.characters.contains("/") else {
        return nil
    }
    // Try to locate in search paths.
    for path in searchPaths {
        let exec = path.appending(component: value)
        if localFileSystem.isExecutableFile(exec) {
            return exec
        }
    }
    return nil
}
