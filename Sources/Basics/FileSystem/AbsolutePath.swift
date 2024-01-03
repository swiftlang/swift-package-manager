//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL
import struct TSCBasic.AbsolutePath
import enum TSCBasic.PathValidationError

// public for transition
public typealias TSCAbsolutePath = TSCBasic.AbsolutePath

/// Represents an absolute file system path, independently of what (or whether
/// anything at all) exists at that path in the file system at any given time.
/// An absolute path always starts with a `/` character, and holds a normalized
/// string representation.  This normalization is strictly syntactic, and does
/// not access the file system in any way.
///
/// The absolute path string is normalized by:
/// - Collapsing `..` path components
/// - Removing `.` path components
/// - Removing any trailing path separator
/// - Removing any redundant path separators
///
/// This string manipulation may change the meaning of a path if any of the
/// path components are symbolic links on disk.  However, the file system is
/// never accessed in any way when initializing an AbsolutePath.
///
/// Note that `~` (home directory resolution) is *not* done as part of path
/// normalization, because it is normally the responsibility of the shell and
/// not the program being invoked (e.g. when invoking `cd ~`, it is the shell
/// that evaluates the tilde; the `cd` command receives an absolute path).
public struct AbsolutePath: Hashable, Sendable {
    /// Root directory (whose string representation is just a path separator).
    
    // FIXME: cross platform
    private static let rootString = "/"
    public static let root = try! Self(validating:  Self.rootString)

    internal let underlying: URL

    public init(validating url: URL) throws {
        if url.relativePath.starts(with: "~") {
            throw TSCBasic.PathValidationError.startsWithTilde(url.standardized.relativePath)
        } else if !url.relativePath.starts(with: Self.rootString) {
            throw TSCBasic.PathValidationError.invalidAbsolutePath(url.standardized.relativePath)
        }
        self.underlying = url.standardized
    }

    /// Initializes the AbsolutePath from `absStr`, which must be an absolute
    /// path (i.e. it must begin with a path separator; this initializer does
    /// not interpret leading `~` characters as home directory specifiers).
    /// The input string will be normalized if needed, as described in the
    /// documentation for AbsolutePath.
    public init(validating pathString: String) throws {
        try self.init(validating: URL(fileURLWithPath: pathString))
    }

    /// Initializes an AbsolutePath from a string that may be either absolute
    /// or relative; if relative, `basePath` is used as the anchor; if absolute,
    /// it is used as is, and in this case `basePath` is ignored.
    public init(validating pathString: String, relativeTo basePath: AbsolutePath) throws {
        if let relativePath = try? RelativePath(validating: pathString) {
            self.init(basePath, relativePath)
        } else {
            try self.init(validating: pathString)
        }
    }

    /// Initializes the AbsolutePath by concatenating a relative path to an
    /// existing absolute path, and renormalizing if necessary.
    public init(_ basePath: AbsolutePath, _ relative: RelativePath) {
        self = basePath.appending(components: relative.components)
    }

    /// Convenience initializer that appends a string to a relative path.
    public init(_ basePath: AbsolutePath, validating relativePathString: String) throws {
        try self.init(basePath, RelativePath(validating: relativePathString))
    }

    /// Directory component.  An absolute path always has a non-empty directory
    /// component (the directory component of the root path is the root itself).
    public var dirname: String {
        self.parentDirectory.pathString
    }

    /// Last path component (including the suffix, if any).  it is never empty.
    public var basename: String {
        let basename = self.underlying.lastPathComponent
        return basename.isEmpty ? Self.root.basename : basename
    }

    /// Returns the basename without the extension.
    public var basenameWithoutExt: String {
        let basename = self.underlying.deletingPathExtension().lastPathComponent
        return basename.isEmpty ? Self.root.basenameWithoutExt : basename
    }

    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix, nor is a
    /// trailing `.` character.
    public var suffix: String? {
        self.extension.map{ ".\($0)" }
    }

    /// Extension of the give path's basename. This follow same rules as
    /// suffix except that it doesn't include leading `.` character.
    public var `extension`: String? {
        let `extension` = self.underlying.pathExtension
        return `extension`.isEmpty ? .none : `extension`
    }

    /// Absolute path of parent directory.  This always returns a path, because
    /// every directory has a parent (the parent directory of the root directory
    /// is considered to be the root directory itself).
    public var parentDirectory: AbsolutePath {
        guard !self.isRoot else {
            return self
        }
        // try! safe
        return try! Self(validating: self.underlying.deletingLastPathComponent())
    }

    /// True if the path is the root directory.
    public var isRoot: Bool {
        self == Self.root
    }

    /// NOTE: We will most likely want to add other `appending()` methods, such
    ///       as `appending(suffix:)`, and also perhaps `replacing()` methods,
    ///       such as `replacing(suffix:)` or `replacing(basename:)` for some
    ///       of the more common path operations.

    /// NOTE: We may want to consider adding operators such as `+` for appending
    ///       a path component.

    /// NOTE: We will want to add a method to return the lowest common ancestor
    ///       path.

    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var pathString: String {
        if self.components.count <= 1 {
            return Self.rootString
        }
        // FIXME: cross platform
        return Self.rootString +
            self.components
            .filter{ $0 != "/" }
            .compactMap { $0.removingPercentEncoding}
            .joined(separator: "/")

        // FIXME: meh
        /*
        var pathString = self.underlying.absoluteString
            .spm_dropPrefix("file://")
            .removingPercentEncoding!
        
        while pathString.hasSuffix("/") {
            pathString = pathString.spm_dropSuffix("/")
        }

        if pathString.count == 0 || pathString == Self.rootString {
            return Self.rootString
        } else {
            return pathString
        }*/
    }
}

extension AbsolutePath {
    /// Returns an array of strings that make up the path components of the
    /// absolute path.  This is the same sequence of strings as the basenames
    /// of each successive path component, starting from the root.  Therefore
    /// the first path component of an absolute path is always `/`.
    public var components: [String] {
        let components = self.underlying.pathComponents
        return components.isEmpty ? Self.root.components : components
    }

    /// Returns the absolute path with the relative path applied.
    public func appending(_ relativePath: RelativePath) -> AbsolutePath {
        self.appending(components: relativePath.components)
    }

    /// Returns the absolute path with an additional literal component appended.
    ///
    /// This method accepts pseudo-path like '.' or '..', but should not contain "/".
    public func appending(component: String) -> AbsolutePath {
        self.appending(components: component)
    }

    /// Returns the absolute path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(components: [String]) -> AbsolutePath {
        // FIXME: find a more efficient way
        var url = self.underlying
        for component in components {
            url = url.appendingPathComponent(component)
        }
        // try! safe
        return try! Self(validating: url)
    }

    /// Returns the absolute path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(components: String...) -> AbsolutePath {
        self.appending(components: components)
    }

    /// Returns the absolute path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(_ component: String) -> AbsolutePath {
        self.appending(component: component)
    }

    /// Returns the absolute path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(_ components: String...) -> AbsolutePath {
        self.appending(components: components)
    }

    /// Returns the absolute path with additional extension appended.
    ///
    public func appending(extension: String) -> AbsolutePath {
        guard !self.isRoot else {
            return self
        }
        let `extension` = `extension`.spm_dropPrefix(".")
        return self.parentDirectory.appending("\(self.basename).\(`extension`)")
    }
}

extension AbsolutePath {
    /// Returns a relative path that, when concatenated to `base`, yields the
    /// callee path itself.  If `base` is not an ancestor of the callee, the
    /// returned path will begin with one or more `..` path components.
    ///
    /// Because both paths are absolute, they always have a common ancestor
    /// (the root path, if nothing else).  Therefore, any path can be made
    /// relative to any other path by using a sufficient number of `..` path
    /// components.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.  Therefore, it does not take symbolic links into account.
    // FIXME: copied from TSC, need to audit
    public func relative(to base: AbsolutePath) -> RelativePath {
        let result: RelativePath
        // Split the two paths into their components.
        // FIXME: The is needs to be optimized to avoid unncessary copying.
        let pathComps = self.components
        let baseComps = base.components

        // It's common for the base to be an ancestor, so try that first.
        if pathComps.starts(with: baseComps) {
            // Special case, which is a plain path without `..` components.  It
            // might be an empty path (when self and the base are equal).
            let relComps = pathComps.dropFirst(baseComps.count)
#if os(Windows)
            let pathString = relComps.joined(separator: "\\")
#else
            let pathString = relComps.joined(separator: "/")
#endif
            do {
                result = try RelativePath(validating: pathString)
            } catch {
                preconditionFailure("invalid relative path computed from \(pathString)")
            }

        } else {
            // General case, in which we might well need `..` components to go
            // "up" before we can go "down" the directory tree.
            var newPathComps = ArraySlice(pathComps)
            var newBaseComps = ArraySlice(baseComps)
            while newPathComps.prefix(1) == newBaseComps.prefix(1) {
                // First component matches, so drop it.
                newPathComps = newPathComps.dropFirst()
                newBaseComps = newBaseComps.dropFirst()
            }
            // Now construct a path consisting of as many `..`s as are in the
            // `newBaseComps` followed by what remains in `newPathComps`.
            var relComps = Array(repeating: "..", count: newBaseComps.count)
            relComps.append(contentsOf: newPathComps)
#if os(Windows)
            let pathString = relComps.joined(separator: "\\")
#else
            let pathString = relComps.joined(separator: "/")
#endif
            do {
                result = try RelativePath(validating: pathString)
            } catch {
                preconditionFailure("invalid relative path computed from \(pathString)")
            }
        }

        assert(AbsolutePath(base, result) == self)
        return result
    }

    /// Returns true if the path is an ancestor of the given path.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.
    public func isAncestor(of descendant: AbsolutePath) -> Bool {
        return descendant.components.dropLast().starts(with: self.components)
    }

    /// Returns true if the path is an ancestor of or equal to the given path.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.
    public func isAncestorOfOrEqual(to descendant: AbsolutePath) -> Bool {
        return descendant.components.starts(with: self.components)
    }

    /// Returns true if the path is a descendant of the given path.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.
    public func isDescendant(of ancestor: AbsolutePath) -> Bool {
        return self.components.dropLast().starts(with: ancestor.components)
    }

    /// Returns true if the path is a descendant of or equal to the given path.
    ///
    /// This method is strictly syntactic and does not access the file system
    /// in any way.
    public func isDescendantOfOrEqual(to ancestor: AbsolutePath) -> Bool {
        return self.components.starts(with: ancestor.components)
    }
}

extension AbsolutePath {
    /// Unlike ``AbsolutePath//extension``, this property returns all characters after the first `.` character in a
    /// filename. If no dot character is present in the filename or first dot is the last character, `nil` is returned.
    public var allExtensions: [String]? {
        guard let firstDot = self.basename.firstIndex(of: ".") else {
            return nil
        }

        var extensions = String(self.basename[firstDot ..< self.basename.endIndex])

        guard extensions.count > 1 else {
            return nil
        }

        extensions.removeFirst()

        return extensions.split(separator: ".").map(String.init)
    }

    /// Returns the basename dropping any possible  extension.
    public var basenameWithoutAnyExtension: String {
        var basename = self.basename
        if let index = basename.firstIndex(of: ".") {
            basename.removeSubrange(index ..< basename.endIndex)
        }
        return String(basename)
    }
}

extension AbsolutePath: Codable {
    // persevere backwards compatibility
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.pathString)
    }

    // persevere backwards compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }
}

extension AbsolutePath: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.components == rhs.components
    }
}

extension AbsolutePath: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.pathString < rhs.pathString
    }
}

/// Make absolute paths CustomStringConvertible and CustomDebugStringConvertible.
extension AbsolutePath: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        self.pathString
    }

    public var debugDescription: String {
        self.underlying.debugDescription
    }
}

extension AbsolutePath {
    public var asURL: Foundation.URL {
        self.underlying
    }
}

// FIXME: for transition
extension AbsolutePath {
    @available(*, deprecated)
    public init(_ underlying: TSCAbsolutePath) {
        // try! safe - we trust TSC path blindly
        try! self.init(validating: underlying.pathString)
    }

    @available(*, deprecated)
    public var asTSCAbsolutePath: TSCAbsolutePath {
        get {
            .init(self.pathString)
        }
    }
}

extension AbsolutePath {
    /// Returns a path suitable for display to the user (if possible, it is made
    /// to be relative to the current working directory).
    // FIXME: copied from TSC, need to audit
    public func prettyPath(cwd: AbsolutePath? = localFileSystem.currentWorkingDirectory) -> String {
        guard let dir = cwd else {
            // No current directory, display as is.
            return self.pathString
        }
        // FIXME: Instead of string prefix comparison we should add a proper API
        // to AbsolutePath to determine ancestry.
        if self == dir {
            return "."
        } else if self.pathString.hasPrefix(dir.pathString + "/") {
            return "./" + self.relative(to: dir).pathString
        } else {
            return self.pathString
        }
    }
}

extension AbsolutePath {
    public var escapedPathString: String {
        self.pathString.replacingOccurrences(of: "\\", with: "\\\\")
    }
}
