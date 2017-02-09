/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

public struct ToolsVersion: Comparable {

    /// The name of the file which contains tools version.
    public static let toolsVersionFileName = ".swift-version"

    /// The default tool version if a the tools version file is absent.
    public static let defaultToolsVersion = try! ToolsVersion(string: "3.1.0")

    /// The current tools version in use.
    public static let currentToolsVersion = try! ToolsVersion(
        string: "\(Versioning.currentVersion.major).\(Versioning.currentVersion.minor).\(Versioning.currentVersion.patch)")

    // FIXME: Temporarily use version as backing storage. We need to figure out exactly how we want
    // to represent tools version.
    private let _version: Version

    /// Create an instance of tools version from a given string.
    // FIXME: We should probably get rid of this init once we know the proper backing store of tools version.
    public init(string: String) throws {
        _version = try Version(string: string)
    }

    // MARK:- Comparable

    public static func ==(lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version == rhs._version
    }

    public static func <(lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }

    public var description: String {
        return _version.description
    }
}
