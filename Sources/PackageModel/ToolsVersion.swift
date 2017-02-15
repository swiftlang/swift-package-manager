/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Utility

/// Tools version represents version of the Swift toolchain.
public struct ToolsVersion: CustomStringConvertible, Comparable {

    /// The name of the file which contains tools version.
    public static let toolsVersionFileName = Manifest.filename

    /// The default tool version if a the tools version file is absent.
    public static let defaultToolsVersion = ToolsVersion(version: "3.1.0")

    /// The current tools version in use.
    public static let currentToolsVersion = ToolsVersion(
        string: "\(Versioning.currentVersion.major).\(Versioning.currentVersion.minor).\(Versioning.currentVersion.patch)")!

    /// The major version number.
    public var major: Int {
        return _version.major
    }

    /// The minor version number.
    public var minor: Int {
        return _version.minor
    }

    /// The patch version number.
    public var patch: Int {
        return _version.patch
    }

    /// The underlying backing store.
    private let _version: Version

    /// Create an instance of tools version from a given string.
    public init?(string: String) {
        let requiredComponents = string.characters.split(separator: ".", maxSplits: 2).map(String.init)
        // We only support Major.Minor or Major.Minor.Patch
        guard requiredComponents.count == 2 || requiredComponents.count == 3 else {
            return nil
        }
        let intComponents = requiredComponents.flatMap(Int.init).filter{ $0>=0 }
        // All components should be integers greater than equal to zero.
        guard requiredComponents.count == intComponents.count else {
            return nil
        }
        _version = Version(intComponents[0], intComponents[1], intComponents.count == 3 ? intComponents[2] : 0)
    }

    /// Create instance of tools version from a given version.
    ///
    /// - precondition: prereleaseIdentifiers and buildMetadataIdentifier should not be present.
    public init(version: Version) {
        precondition(version.prereleaseIdentifiers == [] && version.buildMetadataIdentifier == nil)
        _version = version
    }

    // MARK:- CustomStringConvertible

    public var description: String {
        return _version.description
    }

    // MARK:- Comparable

    public static func ==(lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version == rhs._version
    }

    public static func <(lhs: ToolsVersion, rhs: ToolsVersion) -> Bool {
        return lhs._version < rhs._version
    }
}
