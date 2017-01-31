/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import PackageModel
import Utility

/// Protocol for the manifest loader interface.
public protocol ToolsVersionLoaderProtocol {
    func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion
}

public class ToolsVersionLoader: ToolsVersionLoaderProtocol {
    public init() {
    }

    public enum Error: Swift.Error, Equatable {
        case malformed(file: AbsolutePath)
        case unknown

        public static func ==(lhs: Error, rhs: Error) -> Bool {
            switch (lhs, rhs) {
            case (.malformed(let lhs), .malformed(let rhs)):
                return lhs == rhs
            case (.malformed, _):
                return false
            case (.unknown, .unknown):
                return true
            case (.unknown, _):
                return false
            }
        }
    }

    public func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        let swiftVersion = path.appending(component: ToolsVersion.toolsVersionFileName)
        // If the swift-version file is absent from disk, assume the default version of tools.
        guard fileSystem.isFile(swiftVersion) else {
            return ToolsVersion.defaultToolsVersion
        }
        // Make sure file is readable.
        guard let contents = try fileSystem.readFileContents(swiftVersion).asString?.chomp() else {
            throw Error.malformed(file: swiftVersion)
        }
        // If file is empty, load the default tools version.
        guard !contents.isEmpty else {
            return ToolsVersion.defaultToolsVersion
        }
        // FIXME: Temporary, this can just loads semver right now. We should be able to parse
        // and resolve toolchain names to a tools-version.
        do {
            return try ToolsVersion(string: contents)
        } catch {
            throw Error.unknown
        }
    }
}
