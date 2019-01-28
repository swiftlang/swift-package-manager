/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import SPMLibc
import POSIX
import Foundation

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
    currentWorkingDirectory: AbsolutePath?
) -> [AbsolutePath] {
    // Compute search paths from PATH variable.
    return (pathString ?? "").split(separator: ":").map(String.init).compactMap({ pathString in
        // If this is an absolute path, we're done.
        if pathString.first == "/" {
            return AbsolutePath(pathString)
        }
        // Otherwise convert it into absolute path relative to the working directory.
        guard let cwd = currentWorkingDirectory else {
            return nil
        }
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
///   - currentWorkingDirectory: The current working directory to look in.
///   - searchPaths: The additional search paths to look in if not found in cwd.
/// - Returns: Valid path to executable if present, otherwise nil.
public func lookupExecutablePath(
    filename value: String?,
    currentWorkingDirectory: AbsolutePath? = localFileSystem.currentWorkingDirectory,
    searchPaths: [AbsolutePath] = []
) -> AbsolutePath? {

    // We should have a value to continue.
    guard let value = value, !value.isEmpty else {
        return nil
    }

    let path: AbsolutePath
    if let cwd = currentWorkingDirectory {
        // We have a value, but it could be an absolute or a relative path.
        path = AbsolutePath(value, relativeTo: cwd)
    } else if let absPath = try? AbsolutePath(validating: value) {
        // Current directory not being available is not a problem
        // for the absolute-specified paths.
        path = absPath
    } else {
        return nil
    }

    if localFileSystem.isExecutableFile(path) {
        return path
    }
    // Ensure the value is not a path.
    guard !value.contains("/") else {
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

/// A wrapper for Range to make it Codable.
///
/// Technically, we can use conditional conformance and make
/// stdlib's Range Codable but since extensions leak out, it
/// is not a good idea to extend types that you don't own.
///
/// Range conformance will be added soon to stdlib so we can remove
/// this type in the future.
public struct CodableRange<Bound> where Bound: Comparable & Codable {

    /// The underlying range.
    public let range: Range<Bound>

    /// Create a CodableRange instance.
    public init(_ range: Range<Bound>) {
        self.range = range
    }
}

extension CodableRange: Codable {
    private enum CodingKeys: String, CodingKey {
        case lowerBound, upperBound
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(range.lowerBound, forKey: .lowerBound)
        try container.encode(range.upperBound, forKey: .upperBound)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lowerBound = try container.decode(Bound.self, forKey: .lowerBound)
        let upperBound = try container.decode(Bound.self, forKey: .upperBound)
        self.init(Range(uncheckedBounds: (lowerBound, upperBound)))
    }
}

extension AbsolutePath {
    /// File URL created from the normalized string representation of the path.
    public var asURL: Foundation.URL {
         return URL(fileURLWithPath: pathString)
    }
}
