/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageModel
import TSCUtility
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

extension Manifest {
    /// Returns the manifest at the given package path.
    ///
    /// Version specific manifest is chosen if present, otherwise path to regular
    /// manfiest is returned.
    public static func path(
        atPackagePath packagePath: AbsolutePath,
        currentToolsVersion: ToolsVersion = .currentToolsVersion,
        fileSystem: FileSystem
    ) throws -> AbsolutePath {
        // Look for a version-specific manifest.
        for versionSpecificKey in Versioning.currentVersionSpecificKeys {
            let versionSpecificPath = packagePath.appending(component: Manifest.basename + versionSpecificKey + ".swift")
            if fileSystem.isFile(versionSpecificPath) {
                return versionSpecificPath
            }
        }

        // Otherwise, check if there is a version-specific manifest that has
        // a higher tools version than the main Package.swift file.
        let contents: [String]
        do { contents = try fileSystem.getDirectoryContents(packagePath) } catch {
            throw ToolsVersionLoader.Error.inaccessiblePackage(path: packagePath, reason: String(describing: error))
        }
        let regex = try! RegEx(pattern: "^Package@swift-(\\d+)(?:\\.(\\d+))?(?:\\.(\\d+))?.swift$")

        // Collect all version-specific manifests at the given package path.
        let versionSpecificManifests = Dictionary(contents.compactMap{ file -> (ToolsVersion, String)? in
            let parsedVersion = regex.matchGroups(in: file)
            guard parsedVersion.count == 1, parsedVersion[0].count == 3 else {
                return nil
            }

            let major = Int(parsedVersion[0][0])!
            let minor = parsedVersion[0][1].isEmpty ? 0 : Int(parsedVersion[0][1])!
            let patch = parsedVersion[0][2].isEmpty ? 0 : Int(parsedVersion[0][2])!

            return (ToolsVersion(version: Version(major, minor, patch)), file)
        }, uniquingKeysWith: { $1 })

        let regularManifest = packagePath.appending(component: filename)
        let toolsVersionLoader = ToolsVersionLoader(currentToolsVersion: currentToolsVersion)

        // Find the version-specific manifest that statisfies the current tools version.
        if let versionSpecificCandidate = versionSpecificManifests.keys.sorted(by: >).first(where: { $0 <= currentToolsVersion }) {
            let versionSpecificManifest = packagePath.appending(component: versionSpecificManifests[versionSpecificCandidate]!)

            // Compare the tools version of this manifest with the regular
            // manifest and use the version-specific manifest if it has
            // a greater tools version.
            let versionSpecificManifestToolsVersion = try toolsVersionLoader.load(file: versionSpecificManifest, fileSystem: fileSystem)
            let regularManifestToolsVersion = try toolsVersionLoader.load(file: regularManifest, fileSystem: fileSystem)
            if versionSpecificManifestToolsVersion > regularManifestToolsVersion {
                return versionSpecificManifest
            }
        }

        return regularManifest
    }
}

public class ToolsVersionLoader: ToolsVersionLoaderProtocol {

    let currentToolsVersion: ToolsVersion

    public init(currentToolsVersion: ToolsVersion = .currentToolsVersion) {
        self.currentToolsVersion = currentToolsVersion
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        /// Package directory is inaccessible (missing, unreadable, etc).
        case inaccessiblePackage(path: AbsolutePath, reason: String)
        /// Package manifest file is inaccessible (missing, unreadable, etc).
        case inaccessibleManifest(path: AbsolutePath, reason: String)
        /// Malformed tools version specifier
        case malformedToolsVersion(specifier: String, currentToolsVersion: ToolsVersion)
        // TODO: Make the case more general, to better adapt to future changes.
        /// The spacing between "//" and  "swift-tools-version" either is empty or uses whitespace characters unsupported by Swift ≤ 5.3.
        case invalidSpacingAfterSlashes(charactersUsed: String, specifiedVersion: ToolsVersion)

        public var description: String {
            switch self {
            case .inaccessiblePackage(let packageDir, let reason):
                return "the package at '\(packageDir)' cannot be accessed (\(reason))"
            case .inaccessibleManifest(let manifestFile, let reason):
                return "the package manifest at '\(manifestFile)' cannot be accessed (\(reason))"
            case .malformedToolsVersion(let versionSpecifier, let currentToolsVersion):
                return "the tools version '\(versionSpecifier)' is not valid; consider using '// swift-tools-version:\(currentToolsVersion.major).\(currentToolsVersion.minor)' to specify the current tools version"
            case let .invalidSpacingAfterSlashes(charactersUsed, specifiedVersion):
                // Tell the user what characters are currently used (invalidly) in the specification in place of U+0020.
                let unicodeCodePointsOfCharactersUsed: [UInt32] = charactersUsed.flatMap(\.unicodeScalars).map(\.value)
                let unicodeCodePointsOfCharactersUsedPrefixedByUPlus: [String] = unicodeCodePointsOfCharactersUsed.map { codePoint in
                    var codePointString = String(codePoint, radix: 16).uppercased()
                    if codePointString.count < 4 {
                        codePointString = String(repeating: "0", count: 4 - codePointString.count) + codePointString
                    }
                    return "U+\(codePointString)"
                }
                return "\(charactersUsed.isEmpty ? "zero spacing" : "horizontal whitespace sequence [\(unicodeCodePointsOfCharactersUsedPrefixedByUPlus.joined(separator: ", "))]") between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(specifiedVersion)"
            }
        }
    }

    public func load(at path: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // The file which contains the tools version.
        let file = try Manifest.path(atPackagePath: path, currentToolsVersion: currentToolsVersion, fileSystem: fileSystem)
        guard fileSystem.isFile(file) else {
            // FIXME: We should return an error from here but Workspace tests rely on this in order to work.
            // This doesn't really cause issues (yet) in practice though.
            return ToolsVersion.currentToolsVersion
        }
        return try load(file: file, fileSystem: fileSystem)
    }

    fileprivate func load(file: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // FIXME: We don't need the entire file, just the first line.
        let contents: ByteString
        do { contents = try fileSystem.readFileContents(file) } catch {
            throw Error.inaccessibleManifest(path: file, reason: String(describing: error))
        }
        
        /// The constituent parts of the swift tools version specification found in the comment.
        let deconstructedToolsVersionSpecification = ToolsVersionLoader.split(contents)
        
        // Get the version specifier string from tools version file.
        guard
            let spacingAfterSlashes = deconstructedToolsVersionSpecification.spacingAfterSlashes,
            let versionSpecifier = deconstructedToolsVersionSpecification.versionSpecifier
        else {
            // TODO: Make the diagnsosis more granular by having the regex capture more groups.
            // Try to diagnose if there is a misspelling of the swift-tools-version comment.
            let splitted = contents.contents.split(
                separator: UInt8(ascii: "\n"),
                maxSplits: 1,
                omittingEmptySubsequences: false)
            let misspellings = ["swift-tool", "tool-version"]
            if let firstLine = ByteString(splitted[0]).validDescription,
               misspellings.first(where: firstLine.lowercased().contains) != nil {
                throw Error.malformedToolsVersion(specifier: firstLine, currentToolsVersion: currentToolsVersion)
            }
            // Otherwise assume the default to be v3.
            return .v3
        }

        // Ensure we can construct the version from the specifier.
        guard let version = ToolsVersion(string: versionSpecifier) else {
            throw Error.malformedToolsVersion(specifier: versionSpecifier, currentToolsVersion: currentToolsVersion)
        }
        
        // Ensure that for Swift ≤ 5.3, a single U+0020 is used as spacing between "//" and "swift-tools-version".
		guard spacingAfterSlashes == " " || version > .v5_3 else {
            throw Error.invalidSpacingAfterSlashes(charactersUsed: spacingAfterSlashes, specifiedVersion: version)
        }
        
        return version
    }

    /// Splits the bytes to constituent parts of the swift tools version specification and rest of the contents.
    ///
    /// The constituent parts include the spacing between "//" and "swift-tools-version", and the version specifier, if either is present.
    ///
    /// - Parameter bytes: The raw bytes of the content of the manifest.
    /// - Returns: The spacing between "//" and "swift-tools-version" (if present, or `nil`), the version specifier (if present, or `nil`), and of raw bytes of the rest of the content of the manifest.
    public static func split(_ bytes: ByteString) -> (spacingAfterSlashes: String?, versionSpecifier: String?, rest: [UInt8]) {
        let splitted = bytes.contents.split(
            separator: UInt8(ascii: "\n"),
            maxSplits: 1,
            omittingEmptySubsequences: false)
        // Try to match our regex and see if a valid specifier line.
        guard let firstLine = ByteString(splitted[0]).validDescription,
              let match = ToolsVersionLoader.regex.firstMatch(
                  in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.count)),
              // The 3 ranges are:
              //   1. The entire matched string.
              //   2. Capture group 1: the comment spacing.
              //   3. Capture group 2: The version specifier.
              // Since the version specifier is in the last range, if the number of ranges is less than 3, then no version specifier is captured by the regex.
              // FIXME: Should this be `== 3` instead?
              match.numberOfRanges >= 3 else {
            return (nil, nil, bytes.contents)
        }
        let spacingAfterSlashes = NSString(string: firstLine).substring(with: match.range(at: 1))
        let versionSpecifier = NSString(string: firstLine).substring(with: match.range(at: 2))
        // FIXME: We can probably optimize here and return array slice.
        return (spacingAfterSlashes, versionSpecifier, splitted.count == 1 ? [] : Array(splitted[1]))
    }

    /// The regex to match swift tools version specification.
    ///
    /// The specification must have the following format:
    /// - It should start with `//` followed by any amount of _horizontal_ whitespace characters.
    /// - Following that it should contain the case insensitive string `swift-tools-version:`.
    /// - The text between the above string and `;` or string end becomes the tools version specifier.
    ///
    /// There are 2 capture groups in the regex pattern:
    /// 1. The continuous sequence of whitespace characters between "//" and "swift-tools-version".
    /// 2. The version specifier.
    static let regex = try! NSRegularExpression(
        // The pattern is a raw string, so backslashes should not be escaped.
        pattern: #"^//(\h*?)swift-tools-version:(.*?)(?:;.*|$)"#,
        options: [.caseInsensitive])
}
