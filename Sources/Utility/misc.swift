/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// Get clang's version from the given version output string on Ubuntu.
public func getClangVersion(versionOutput: String) -> (major: Int, minor: Int)? {
    // Clang outputs version in this format on Ubuntu:
    // Ubuntu clang version 3.6.0-2ubuntu1~trusty1 (tags/RELEASE_360/final) (based on LLVM 3.6.0)
    let versionStringPrefix = "Ubuntu clang version "
    let versionStrings = versionOutput.utf8.split(separator: UInt8(ascii: "-")).flatMap(String.init)
    guard let clangVersionString = versionStrings.first,
          clangVersionString.hasPrefix(versionStringPrefix) else {
        return nil
    }
    let versionStartIndex = clangVersionString.index(clangVersionString.startIndex, offsetBy: versionStringPrefix.utf8.count)
    let versionString: String = clangVersionString[versionStartIndex..<clangVersionString.endIndex]
    // Split major minor patch etc.
    let versions = versionString.utf8.split(separator: UInt8(ascii: ".")).flatMap(String.init)
    guard versions.count > 1, let major = Int(versions[0]), let minor = Int(versions[1]) else {
        return nil
    }
    return (major, minor)
}

// MARK: utility function for searching for executables

/// Create a list of AbsolutePath search paths from a string, such as the PATH environment variable.
///
/// - Parameters:
///   - pathString: The path string to parse.
///   - currentWorkingDirectory: The current working directory, the relative paths will be converted to absolute paths based on this path.
/// - Returns: List of search paths.
public func getEnvSearchPaths(
    pathString: String?,
    currentWorkingDirectory cwd: AbsolutePath
    ) -> [AbsolutePath] {
    // Compute search paths from PATH variable.
    return (pathString ?? "").characters.split(separator: ":").map(String.init).map { pathString in
        // If this is an absolute path, we're done.
        if pathString.characters.first == "/" {
            return AbsolutePath(pathString)
        }
        // Otherwise convert it into absolute path relative to the working directory.
        return AbsolutePath(pathString, relativeTo: cwd)
    }
}

/// Lookup an executable path from an environment variable value, current working
/// directory or search paths.
///
/// This method searches in the following order:
/// * If env value is a valid absolute path, return it.
/// * If env value is relative path, first try to locate it in current working directory.
/// * Otherwise, in provided search paths.
///
/// - Parameters:
///   - value: The value from environment variable.
///   - cwd: The current working directory to look in.
///   - searchPath: The additional search path to look in if not found in cwd.
/// - Returns: Valid path to executable if present, otherwise nil.
public func lookupExecutablePath(
    inEnvValue value: String?,
    currentWorkingDirectory cwd: AbsolutePath = currentWorkingDirectory,
    searchPaths: [AbsolutePath] = []
    ) -> AbsolutePath? {
    // We should have a value to continue.
    guard let value = value, !value.isEmpty else {
        return nil
    }
    // We have a value, but it could be an absolute or a relative path.
    let path = AbsolutePath(value, relativeTo: cwd)
    if exists(path) {
        return path
    }
    // Ensure the value is not a path.
    guard !value.characters.contains("/") else {
        return nil
    }
    // Try to locate in search paths.
    for path in searchPaths {
        let exec = path.appending(component: value)
        if exists(exec) {
            return exec
        }
    }
    return nil
}
