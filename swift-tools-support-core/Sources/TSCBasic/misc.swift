/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCLibc
import Foundation

#if os(Windows)
public let executableFileSuffix = ".exe"
#else
public let executableFileSuffix = ""
#endif

/// Replace the current process image with a new process image.
///
/// - Parameters:
///   - path: Absolute path to the executable.
///   - args: The executable arguments.
public func exec(path: String, args: [String]) throws {
    let cArgs = CStringArray(args)
  #if os(Windows)
    guard cArgs.cArray.withUnsafeBufferPointer({
        $0.withMemoryRebound(to: UnsafePointer<Int8>?.self, {
          _execv(path, $0.baseAddress) != -1
        })
    })
    else {
        throw SystemError.exec(errno, path: path, args: args)
    }
  #else
    guard execv(path, cArgs.cArray) != -1 else {
        throw SystemError.exec(errno, path: path, args: args)
    }
  #endif
}

// MARK: TSCUtility function for searching for executables

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
#if os(Windows)
    let pathSeparator: Character = ";"
#else
    let pathSeparator: Character = ":"
#endif
    return (pathString ?? "").split(separator: pathSeparator).map(String.init).compactMap({ pathString in
        if let cwd = currentWorkingDirectory {
            return AbsolutePath(pathString, relativeTo: cwd)
        }
        return try? AbsolutePath(validating: pathString)
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

    var paths: [AbsolutePath] = []

    if let cwd = currentWorkingDirectory {
        // We have a value, but it could be an absolute or a relative path.
        paths.append(AbsolutePath(value, relativeTo: cwd))
    } else if let absPath = try? AbsolutePath(validating: value) {
        // Current directory not being available is not a problem
        // for the absolute-specified paths.
        paths.append(absPath)
    }

    // Ensure the value is not a path.
    if !value.contains("/") {
        // Try to locate in search paths.
        paths.append(contentsOf: searchPaths.map({ $0.appending(component: value) }))
    }

    return paths.first(where: { localFileSystem.isExecutableFile($0) })
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

// FIXME: Eliminate or find a proper place for this.
public enum SystemError: Swift.Error {
    case chdir(Int32, String)
    case close(Int32)
    case exec(Int32, path: String, args: [String])
    case pipe(Int32)
    case posix_spawn(Int32, [String])
    case read(Int32)
    case setenv(Int32, String)
    case stat(Int32, String)
    case symlink(Int32, String, dest: String)
    case unsetenv(Int32, String)
    case waitpid(Int32)
}

#if os(Windows)
import func TSCLibc.strerror_s
#else
import func TSCLibc.strerror_r
#endif
import var TSCLibc.EINVAL
import var TSCLibc.ERANGE

extension SystemError: CustomStringConvertible {
    public var description: String {
        func strerror(_ errno: Int32) -> String {
          #if os(Windows)
            let cap = 128
            var buf = [Int8](repeating: 0, count: cap)
            let _ = TSCLibc.strerror_s(&buf, 128, errno)
            return "\(String(cString: buf)) (\(errno))"
          #else
            var cap = 64
            while cap <= 16 * 1024 {
                var buf = [Int8](repeating: 0, count: cap)
                let err = TSCLibc.strerror_r(errno, &buf, buf.count)
                if err == EINVAL {
                    return "Unknown error \(errno)"
                }
                if err == ERANGE {
                    cap *= 2
                    continue
                }
                if err != 0 {
                    fatalError("strerror_r error: \(err)")
                }
                return "\(String(cString: buf)) (\(errno))"
            }
            fatalError("strerror_r error: \(ERANGE)")
          #endif
        }

        switch self {
        case .chdir(let errno, let path):
            return "chdir error: \(strerror(errno)): \(path)"
        case .close(let errno):
            return "close error: \(strerror(errno))"
        case .exec(let errno, let path, let args):
            let joinedArgs = args.joined(separator: " ")
            return "exec error: \(strerror(errno)): \(path) \(joinedArgs)"
        case .pipe(let errno):
            return "pipe error: \(strerror(errno))"
        case .posix_spawn(let errno, let args):
            return "posix_spawn error: \(strerror(errno)), `\(args)`"
        case .read(let errno):
            return "read error: \(strerror(errno))"
        case .setenv(let errno, let key):
            return "setenv error: \(strerror(errno)): \(key)"
        case .stat(let errno, _):
            return "stat error: \(strerror(errno))"
        case .symlink(let errno, let path, let dest):
            return "symlink error: \(strerror(errno)): \(path) -> \(dest)"
        case .unsetenv(let errno, let key):
            return "unsetenv error: \(strerror(errno)): \(key)"
        case .waitpid(let errno):
            return "waitpid error: \(strerror(errno))"
        }
    }
}

/// Memoizes a costly computation to a cache variable.
public func memoize<T>(to cache: inout T?, build: () throws -> T) rethrows -> T {
    if let value = cache {
        return value
    } else {
        let value = try build()
        cache = value
        return value
    }
}
