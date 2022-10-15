//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_implementationOnly
import struct TSCBasic.AbsolutePath

/// A simple representation of a path in the file system.
public struct Path: Hashable {
    private let _storage: AbsolutePath

    /// Initializes the path from the contents a string, which should be an
    /// absolute path in platform representation.
    public init(_ string: String) {
        self._storage = AbsolutePath(string)
    }

    /// A string representation of the path.
    public var string: String {
        return self._storage.pathString
    }

    /// The last path component (including any extension).
    public var lastComponent: String {
        return _storage.basename
    }

    /// The last path component (without any extension).
    public var stem: String {
        return _storage.basenameWithoutExt
    }

    /// The filename extension, if any (without any leading dot).
    public var `extension`: String? {
        return _storage.extension
    }

    /// The path except for the last path component.
    public func removingLastComponent() -> Path {
        return Path(_storage.dirname)
    }

    /// The result of appending a subpath, which should be a relative path in
    /// platform representation.
    public func appending(subpath: String) -> Path {
        return Path(_storage.appending(component: subpath).pathString)
    }

    /// The result of appending one or more path components.
    public func appending(_ components: [String]) -> Path {
        return Path(_storage.appending(components: components).pathString)
    }

    /// The result of appending one or more path components.
    public func appending(_ components: String...) -> Path {
        return Path(_storage.appending(components: components).pathString)
    }
}

extension Path: CustomStringConvertible {

    public var description: String {
        return self.string
    }
}

extension Path: Codable {

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.string)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self.init(string)
    }
}

public extension String.StringInterpolation {
    
    mutating func appendInterpolation(_ path: Path) {
        self.appendInterpolation(path.string)
    }
}
