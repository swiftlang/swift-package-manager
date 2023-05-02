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

import struct TSCBasic.RelativePath

// public for transition
public typealias TSCRelativePath = TSCBasic.RelativePath

/// Represents a relative file system path.  A relative path never starts with
/// a `/` character, and holds a normalized string representation.  As with
/// AbsolutePath, the normalization is strictly syntactic, and does not access
/// the file system in any way.
///
/// The relative path string is normalized by:
/// - Collapsing `..` path components that aren't at the beginning
/// - Removing extraneous `.` path components
/// - Removing any trailing path separator
/// - Removing any redundant path separators
/// - Replacing a completely empty path with a `.`
///
/// This string manipulation may change the meaning of a path if any of the
/// path components are symbolic links on disk.  However, the file system is
/// never accessed in any way when initializing a RelativePath.
public struct RelativePath: Hashable, Sendable {
    let underlying: TSCBasic.RelativePath

    // public for transition
    public init(_ underlying: TSCBasic.RelativePath) {
        self.underlying = underlying
    }

    /// Convenience initializer that verifies that the path is relative.
    public init(validating pathString: String) throws {
        self.underlying = try .init(validating: pathString)
    }

    /// Directory component.  For a relative path without any path separators,
    /// this is the `.` string instead of the empty string.
    public var dirname: String {
        self.underlying.dirname
    }

    /// Last path component (including the suffix, if any).  It is never empty.
    public var basename: String {
        self.underlying.basename
    }

    /// Returns the basename without the extension.
    public var basenameWithoutExt: String {
        self.underlying.basenameWithoutExt
    }

    /// Suffix (including leading `.` character) if any.  Note that a basename
    /// that starts with a `.` character is not considered a suffix, nor is a
    /// trailing `.` character.
    public var suffix: String? {
        self.underlying.suffix
    }

    /// Extension of the give path's basename. This follow same rules as
    /// suffix except that it doesn't include leading `.` character.
    public var `extension`: String? {
        self.underlying.extension
    }

    /// Normalized string representation (the normalization rules are described
    /// in the documentation of the initializer).  This string is never empty.
    public var pathString: String {
        self.underlying.pathString
    }
}

extension RelativePath {
    /// Returns an array of strings that make up the path components of the
    /// relative path.  This is the same sequence of strings as the basenames
    /// of each successive path component.  Therefore the returned array of
    /// path components is never empty; even an empty path has a single path
    /// component: the `.` string.
    public var components: [String] {
        self.underlying.components
    }

    /// Returns the relative path with the given relative path applied.
    public func appending(_ subpath: RelativePath) -> RelativePath {
        Self(self.underlying.appending(subpath.underlying))
    }

    /// Returns the relative path with an additional literal component appended.
    ///
    /// This method accepts pseudo-path like '.' or '..', but should not contain "/".
    public func appending(component: String) -> RelativePath {
        Self(self.underlying.appending(component: component))
    }

    /// Returns the relative path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(components: [String]) -> RelativePath {
        Self(self.underlying.appending(components: components))
    }

    /// Returns the relative path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(components: String...) -> RelativePath {
        Self(self.underlying.appending(components: components))
    }

    /// Returns the relative path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(_ component: String) -> RelativePath {
        self.appending(component: component)
    }

    /// Returns the relative path with additional literal components appended.
    ///
    /// This method should only be used in cases where the input is guaranteed
    /// to be a valid path component (i.e., it cannot be empty, contain a path
    /// separator, or be a pseudo-path like '.' or '..').
    public func appending(_ components: String...) -> RelativePath {
        self.appending(components: components)
    }
}

extension RelativePath: Codable {
    public func encode(to encoder: Encoder) throws {
        try self.underlying.encode(to: encoder)
    }

    public init(from decoder: Decoder) throws {
        self = try .init(TSCBasic.RelativePath(from: decoder))
    }
}

/// Make relative paths CustomStringConvertible and CustomDebugStringConvertible.
extension RelativePath: CustomStringConvertible {
    public var description: String {
        self.underlying.description
    }

    public var debugDescription: String {
        self.underlying.debugDescription
    }
}

extension TSCRelativePath {
    public init(_ path: RelativePath) {
        self = path.underlying
    }
}
