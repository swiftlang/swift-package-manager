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

    public enum Error: Swift.Error {
        case malformed(specifier: String, file: AbsolutePath)
    }

    public func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // The file which contains the tools version.
        let file = path.appending(component: ToolsVersion.toolsVersionFileName)
        guard fileSystem.isFile(file) else {
            return ToolsVersion.defaultToolsVersion
        }
        // FIXME: We don't need the entire file, just the first line.
        let contents = try fileSystem.readFileContents(file)

        // Get the version specifier string from first line.
        guard let firstLine = ByteString(contents.contents.prefix(while: { $0 != UInt8(ascii: "\n") })).asString, 
              let match = ToolsVersionLoader.regex.firstMatch(
                  in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.characters.count)),
              match.numberOfRanges >= 2 else {
            return ToolsVersion.defaultToolsVersion
        }

        let versionSpecifier = NSString(string: firstLine).substring(with: match.range(at: 1))
        // Ensure we can construct the version from the specifier.
        guard let version = ToolsVersion(string: versionSpecifier) else {
            throw Error.malformed(specifier: versionSpecifier, file: path)
        }
        return version
    }

    // The regex to match swift tools version specification:
    // * It should start with `//` followed by any amount of whitespace.
    // * Following that it should contain the case insensitive string `swift-tools-version:`.
    // * The text between the above string and `;` or string end becomes the tools version specifier.
    static let regex = try! NSRegularExpression(pattern: "^// swift-tools-version:(.*?)(?:;.*|$)", options: [.caseInsensitive])
}

#if os(macOS)
// Compatibility shim.
// <rdar://problem/30488747> NSTextCheckingResult doesn't have range(at:) method
extension NSTextCheckingResult {
    fileprivate func range(at idx: Int) -> NSRange {
        return rangeAt(idx)
    }
}
#endif
