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
import Foundation

/// Protocol for the manifest loader interface.
public protocol ToolsVersionLoaderProtocol {

    /// Load the tools version at the give package path.
    ///
    /// - Parameters:
    ///   - path: The path to the package.
    ///   - fileSystem: The file system to use to read the file which contains tools version.
    /// - Returns: The tools version.
    /// - Throws: ToolsVersion.Error
    func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion
}

public class ToolsVersionLoader: ToolsVersionLoaderProtocol {
    public init() {
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case malformed(specifier: String, file: AbsolutePath)

        public var description: String {
            switch self {
            case .malformed(let versionSpecifier, let file):
                return "The version specifier '\(versionSpecifier)' in '\(file.asString)' is not valid"
            }
        }
    }

    public func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // The file which contains the tools version.
        let file = Manifest.path(atPackagePath: path, fileSystem: fileSystem)
        guard fileSystem.isFile(file) else {
            return ToolsVersion.defaultToolsVersion
        }
        // FIXME: We don't need the entire file, just the first line.
        let contents = try fileSystem.readFileContents(file)

        // Get the version specifier string from tools version file.
        guard let versionSpecifier = ToolsVersionLoader.split(contents).versionSpecifier else {
            // Try to diagnose if there is a misspelling of the swift-tools-version comment.
            let splitted = contents.contents.split(
                separator: UInt8(ascii: "\n"),
                maxSplits: 1,
                omittingEmptySubsequences: false)
            let misspellings = ["swift-tool", "tool-version"]
            if let firstLine = ByteString(splitted[0]).asString,
               misspellings.first(where: firstLine.lowercased().contains) != nil {
                throw Error.malformed(specifier: firstLine, file: file)
            }
            // Otherwise assume the default.
            return ToolsVersion.defaultToolsVersion
        }

        // Ensure we can construct the version from the specifier.
        guard let version = ToolsVersion(string: versionSpecifier) else {
            throw Error.malformed(specifier: versionSpecifier, file: file)
        }
        return version
    }

    /// Splits the bytes to the version specifier (if present) and rest of the contents.
    public static func split(_ bytes: ByteString) -> (versionSpecifier: String?, rest: [UInt8]) {
        let splitted = bytes.contents.split(
            separator: UInt8(ascii: "\n"),
            maxSplits: 1,
            omittingEmptySubsequences: false)
        // Try to match our regex and see if a valid specifier line.
        guard let firstLine = ByteString(splitted[0]).asString,
              let match = ToolsVersionLoader.regex.firstMatch(
                  in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.characters.count)),
              match.numberOfRanges >= 2 else {
            return (nil, bytes.contents)
        }
        let versionSpecifier = NSString(string: firstLine).substring(with: match.range(at: 1))
        // FIXME: We can probably optimize here and return array slice.
        return (versionSpecifier, splitted.count == 1 ? [] : Array(splitted[1]))
    }

    // The regex to match swift tools version specification:
    // * It should start with `//` followed by any amount of whitespace.
    // * Following that it should contain the case insensitive string `swift-tools-version:`.
    // * The text between the above string and `;` or string end becomes the tools version specifier.
    static let regex = try! NSRegularExpression(
        pattern: "^// swift-tools-version:(.*?)(?:;.*|$)",
        options: [.caseInsensitive])
}
