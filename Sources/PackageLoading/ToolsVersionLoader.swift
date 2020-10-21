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
    /// manifest is returned.
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

        // Find the version-specific manifest that satisfies the current tools version.
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
    
    // FIXME: Remove this property and the initializer?
    // Arbitrary tools versions are used only in `ToolsVersionLoaderTests.testVersionSpecificManifestFallbacks()`.
    let currentToolsVersion: ToolsVersion

    public init(currentToolsVersion: ToolsVersion = .currentToolsVersion) {
        self.currentToolsVersion = currentToolsVersion
    }

    // FIXME: Use generic associated type `T: StringProtocol` instead of concrete types `String` and `Substring`, when/if this feature comes to Swift.
    public enum Error: Swift.Error, CustomStringConvertible {
        
        /// Details of the tools version specification's malformation.
        public enum ToolsVersionSpecificationMalformation {
            /// The tools version specification from the first character up to the version specifier is malformed.
            case label(_ label: Substring)
            /// The version specifier is malformed.
            case versionSpecifier(_ versionSpecifier: Substring)
            /// The entire tools version specification is malformed.
            case entireLine(_ line: Substring)
        }
        
        /// Details of backward-incompatible contents with Swift tools version ≤ 5.3.
        public enum BackwardIncompatibilityPre5_3_1 {
            /// The line terminators at the start of the manifest is not either empty or a single `U+000A`.
            case leadingLineTerminators(_ lineTerminators: Substring)
            /// The horizontal spacing between "//" and  "swift-tools-version" either is empty or uses whitespace characters unsupported by Swift ≤ 5.3.
            case spacingAfterSlashes(_ spacing: Substring)
        }
        
        /// Package directory is inaccessible (missing, unreadable, etc).
        case inaccessiblePackage(path: AbsolutePath, reason: String)
        /// Package manifest file is inaccessible (missing, unreadable, etc).
        case inaccessibleManifest(path: AbsolutePath, reason: String)
        /// Package manifest file's content can not be decoded as a UTF-8 string.
        case nonUTF8EncodedManifest(path: AbsolutePath)
        /// Malformed tools version specification.
        case malformedToolsVersionSpecification(_ malformation: ToolsVersionSpecificationMalformation)
        /// Backward-incompatible contents with Swift tools version ≤ 5.3.
        case backwardIncompatiblePre5_3_1(_ incompatibility: BackwardIncompatibilityPre5_3_1, specifiedVersion: ToolsVersion)

        public var description: String {
            
            /// Returns a description of the given characters' Unicode code points.
            ///
            /// This tells the user what characters are currently used in the specification.
            ///
            /// - Parameter characters: The given characters the description of whose code points are to be returned.
            /// - Returns: A list of `characters`' code points, each prefixed by "U+", separated by commas, and bounded together by a pair of square brackets.
            func unicodeCodePointsPrefixedByUPlus<T: StringProtocol>(of characters: T) -> String {
                let unicodeCodePointsOfCharacters: [UInt32] = characters.flatMap(\.unicodeScalars).map(\.value)
                let unicodeCodePointsOfCharactersPrefixedByUPlus: [String] = unicodeCodePointsOfCharacters.map { codePoint in
                    var codePointString = String(codePoint, radix: 16).uppercased()
                    if codePointString.count < 4 {
                        codePointString = String(repeating: "0", count: 4 - codePointString.count) + codePointString
                    }
                    return "U+\(codePointString)"
                }
                // FIXME: Use `ListFormatter` instead?
                return "[\(unicodeCodePointsOfCharactersPrefixedByUPlus.joined(separator: ", "))]"
            }
            
            switch self {
            case let .inaccessiblePackage(packageDirectoryPath, reason):
                return "the package at '\(packageDirectoryPath)' cannot be accessed (\(reason))"
            case let .inaccessibleManifest(manifestFilePath, reason):
                return "the package manifest at '\(manifestFilePath)' cannot be accessed (\(reason))"
            case let .nonUTF8EncodedManifest(manifestFilePath):
                return "the package manifest at '\(manifestFilePath)' cannot be decoded using UTF-8"
            case let .malformedToolsVersion(versionSpecifier, currentToolsVersion):
                return "the tools version '\(versionSpecifier)' is not valid; consider using '// swift-tools-version:\(currentToolsVersion.major).\(currentToolsVersion.minor)' to specify the current tools version"
            case let .malformedToolsVersionSpecification(malformation):
                switch malformation {
                case let .label(label):
                    return "the tools version specification label '\(label)' is malformed; consider using '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current tools version"
                case let .versionSpecifier(versionSpecifier):
                    return "the tools version '\(versionSpecifier)' is not valid; consider using '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current tools version"
                case let .entireLine(line):
                    return "the tools version specification '\(line)' is not valid; consider using '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current tools version"
                }
            // FIXME: The error messages probably can be more concise, while still hitting all the key points.
            case let .backwardIncompatiblePre5_3_1(incompatibility, specifiedVersion):
                switch incompatibility {
                case let .leadingLineTerminators(lineTerminators):
                    return "leading line terminator sequence \(unicodeCodePointsPrefixedByUPlus(of: lineTerminators)) in manifest is supported by only Swift > 5.3; for the specified version \(specifiedVersion), only zero or one newline (U+000A) at the beginning of the manifest is supported; consider moving the tools version specification to the first line of the manifest"
                case let .spacingAfterSlashes(spacing):
                    return "\(spacing.isEmpty ? "zero spacing" : "horizontal whitespace sequence \(unicodeCodePointsPrefixedByUPlus(of: spacing))") between \"//\" and \"swift-tools-version\" is supported by only Swift > 5.3; consider using a single space (U+0020) for Swift \(specifiedVersion)"
                }
            }
            
        }
    }
    
    /// A representation of a manifest in its constituent parts.
    public struct ManifestComponents {
        /// The line terminators at the start of the manifest.
        public let leadingLineTerminators: Substring
        /// The tools version specification, excluding the ending line terminator.
        public let toolsVersionSpecification: Substring
        /// The remaining contents of the manifest that follows right after the tools version specification line.
        public let contentsAfterToolsVersionSpecification: Substring
        /// The components of the tools version specification that are captured by the `regex`.
        public let toolsVersionSpecificationCapturedComponents: ToolsVersionSpecificationCapturedComponents
    }
    
    /// Components of the tools version specification that are captured by the `regex`.
    public struct ToolsVersionSpecificationCapturedComponents {
        /// The horizontal spacing between "//" and  "swift-tools-version".
        public let spacingAfterSlashes: Substring?
        /// The version specifier.
        public let versionSpecifier: Substring?
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

    // FIXME: Using "file" as the parameter name (and label) sounds wrong in some subsequent use of it in the function body.
    // Maybe rename the function as `fileprivate func load(fileAt filePath: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion`?
    fileprivate func load(file: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // FIXME: We don't need the entire file, just the first line.
        let contents: ByteString
        do { contents = try fileSystem.readFileContents(file) } catch {
            throw Error.inaccessibleManifest(path: file, reason: String(describing: error))
        }
        
        // FIXME: This is doubly inefficient.
        // `contents`'s value comes from `FileSystem.readFileContents(_)`, which is [inefficient](https://github.com/apple/swift-tools-support-core/blob/8f9838e5d4fefa0e12267a1ff87d67c40c6d4214/Sources/TSCBasic/FileSystem.swift#L167). Calling `ByteString.validDescription` on `contents` is also [inefficient, and possibly incorrect](https://github.com/apple/swift-tools-support-core/blob/8f9838e5d4fefa0e12267a1ff87d67c40c6d4214/Sources/TSCBasic/ByteString.swift#L121). However, this is a one-time thing for each package manifest, and almost necessary in order to work with all Unicode line-terminators. We probably can improve its efficiency and correctness by using `URL` for the file's path, and get is content via `Foundation.String(contentsOf:encoding:)`. Swift System's [`FilePath`](https://github.com/apple/swift-system/blob/8ffa04c0a0592e6f4f9c30926dedd8fa1c5371f9/Sources/System/FilePath.swift) and friends might help as well.
        // FIXME: This is source-breaking.
        // A manifest that has an [invalid byte sequence](https://en.wikipedia.org/wiki/UTF-8#Invalid_sequences_and_error_handling) (such as `0x7F8F`) after the tools version specification line could work in Swift ≤ 5.3, but results in an error since Swift 5.3.1.
        guard let contentsDecodedWithUTF8 = contents.validDescription else {
            throw Error.nonUTF8EncodedManifest(path: file)
        }
        
        /// The constituent parts of the swift tools version specification found in the comment.
        let manifestComponents = ToolsVersionLoader.split(contentsDecodedWithUTF8)
        let toolsVersionSpecificationComponents = manifestComponents.toolsVersionSpecificationCapturedComponents
        
        // Get the version specifier string from tools version file.
        guard
            let spacingAfterSlashes = toolsVersionSpecificationComponents.spacingAfterSlashes,
            let versionSpecifier = toolsVersionSpecificationComponents.versionSpecifier
        else {
            // TODO: Make the diagnosis more granular by having the regex capture more groups.
            // Try to diagnose if there is a misspelling of the swift-tools-version comment.
            let toolsVersionSpecification = manifestComponents.toolsVersionSpecification
            let misspellings = ["swift-tool", "tool-version"]
            if misspellings.first(where: toolsVersionSpecification.lowercased().contains) != nil {
                throw Error.malformedToolsVersionSpecification(.entireLine(toolsVersionSpecification))
            }
            // Otherwise assume the default to be v3.
            return .v3
        }
        
        // Ensure we can construct the version from the specifier.
        guard let version = ToolsVersion(string: String(versionSpecifier)) else {
            throw Error.malformedToolsVersionSpecification(.versionSpecifier(versionSpecifier))
        }
        
        // The order of the following `guard` statements must be preserved.
        // It translates to the precedence of the error to throw.
        // If the order is changed, the test cases in `ToolsVersionLoaderTests.testBackwardCompatibilityError()` must also be changed accordingly.
        
        // Ensure that for Swift ≤ 5.3, only 0 or 1 U+000A and nothing else is before the tools version specification.
        guard version > .v5_3 || manifestComponents.leadingLineTerminators.isEmpty || manifestComponents.leadingLineTerminators == "\n" else {
            throw Error.backwardIncompatiblePre5_3_1(.leadingLineTerminators(manifestComponents.leadingLineTerminators), specifiedVersion: version)
        }
        
        // Ensure that for Swift ≤ 5.3, exactly a single U+0020 is used as spacing between "//" and "swift-tools-version".
        guard version > .v5_3 || spacingAfterSlashes == " " else {
            throw Error.backwardIncompatiblePre5_3_1(.spacingAfterSlashes(spacingAfterSlashes), specifiedVersion: version)
        }
        
        return version
    }
    
    // FIXME: Remove this function?
    // This function is currently preserved because it's declared as public.
    // Removing it is probably source-breaking.
    /// Splits the bytes to find the Swift tools version specifier and the contents sans the first line of the manifest.
    ///
    /// - Warning: This function has been deprecated since Swift 5.3.1, please use `split(_ manifestContents: String) -> ManifestComponents` instead.
    ///
    /// - Bug: This function treats only `U+000A` as a line terminator.
    ///
    /// - Bug: If there is a single leading `U+000A` in the manifest file, this function treats the second line of the manifest as its first line.
    ///
    /// - Parameter bytes: The raw bytes of the content of the manifest.
    /// - Returns: The version specifier (if present, or `nil`) and the raw bytes of the contents sans the first line of the manifest.
    @available(swift, deprecated: 5.3.1, renamed: "ToolsVersionLoader.split(_:)")
    public static func split(_ bytes: ByteString) -> (versionSpecifier: String?, rest: [UInt8]) {
        let splitted = bytes.contents.split(
            separator: UInt8(ascii: "\n"),
            maxSplits: 1,
            omittingEmptySubsequences: false)
        // Try to match our regex and see if the "first" line is a valid tools version specification line.
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
            return (nil, bytes.contents)
        }
        let versionSpecifier = NSString(string: firstLine).substring(with: match.range(at: 2))
        // FIXME: We can probably optimize here and return array slice.
        return (versionSpecifier, splitted.count == 1 ? [] : Array(splitted[1]))
    }
    
    /// Splits the given manifest into its constituent components.
    ///
    /// The components include the leading line terminators, the tools version specification, and the rest of the manifest. Spacing between "//" and "swift-tools-version" and the version specifier are included separately, if found in the tools version specification.
    ///
    /// - Parameter manifestContents: The UTF-8-encoded content of the manifest.
    /// - Returns: The components of the given manifest.
    public static func split(_ manifestContents: String) -> ManifestComponents {
        
        // We split the string manually instead of using `split(maxSplits:omittingEmptySubsequences:whereSeparator:)`,
        // because the latter method fails in the edge case where the manifest starts with a single line terminator.
        
        /// The position of the first character of the tools version specification line in the manifest.
        ///
        /// Because the tools version specification is the first non-empty line in the manifest, the position of its first character is also the position of the first non-line-terminating character in the manifest.
        let startIndexOfToolsVersionSpecification = manifestContents.firstIndex(where: { !$0.isNewline } ) ?? manifestContents.startIndex
        
        /// The line terminators at the start of the manifest.
        ///
        /// Because the tools version specification is the first non-empty line in the manifest, the manifest's leading line terminators are the only characters in front of the tools version specification.
        let leadingLineTerminators = manifestContents[..<startIndexOfToolsVersionSpecification]
        
        /// The position right past the last character of the tools version specification line in the manifest.
        ///
        /// Because the tools version specification is the first non-empty line in the manifest, the position right past its last character is the position of the first non-leading line terminator in the manifest. If no such line terminator exists, then the position is the `endIndex` of the manifest.
        let endIndexOfToolsVersionSpecification = manifestContents[startIndexOfToolsVersionSpecification...].firstIndex(where: \.isNewline) ?? manifestContents.endIndex
        
        /// The Swift tools version specification.
        ///
        /// The specification is the first comment in the manifest that declares the version of the `PackageDescription` library, the minimum version of the Swift tools and Swift language compatibility version to process the manifest, and the minimum version of the Swift tools that are needed to use the Swift package.
        let toolsVersionSpecification = manifestContents[startIndexOfToolsVersionSpecification..<endIndexOfToolsVersionSpecification]
        
        /// The position of the first character of the tools version specification line in the manifest.
        ///
        /// If no such character exists, then the position is the `endIndex` of the manifest.
        let startIndexOfManifestContentsAfterToolsVersionSpecification = endIndexOfToolsVersionSpecification == manifestContents.endIndex ? manifestContents.endIndex : manifestContents.index(after: endIndexOfToolsVersionSpecification)
        
        /// The remaining contents of the manifest that follows right after the tools version specification line.
        let manifestContentsAfterToolsVersionSpecification = manifestContents[startIndexOfManifestContentsAfterToolsVersionSpecification...]
        
        // `NSRegularExpression.firstMatch(in:options:range:)` accepts only a `String` instance as the first parameter.
        /// The string of the Swift tools version specification.
        let toolsVersionSpecificationString = String(toolsVersionSpecification)
        
        // Try to match our regex and see if the tools version specification is valid.
        guard
            let match = regex.firstMatch(in: toolsVersionSpecificationString, options: [], range: NSRange(toolsVersionSpecificationString.startIndex..<toolsVersionSpecificationString.endIndex, in: toolsVersionSpecificationString)),
            // The 3 ranges are:
            //   1. The entire matched string.
            //   2. Capture group 1: the comment spacing.
            //   3. Capture group 2: The version specifier.
            // Since the version specifier is in the last range, if the number of ranges is less than 3, then no version specifier is captured by the regex.
            // FIXME: Should this be `== 3` instead?
            match.numberOfRanges >= 3
        else {
            return ManifestComponents(
                leadingLineTerminators: leadingLineTerminators,
                toolsVersionSpecification: toolsVersionSpecification,
                contentsAfterToolsVersionSpecification: manifestContentsAfterToolsVersionSpecification,
                toolsVersionSpecificationCapturedComponents: ToolsVersionSpecificationCapturedComponents(spacingAfterSlashes: nil, versionSpecifier: nil)
            )
        }
        
        // Try to match our regex and see if the tools version specification is valid.
        guard let rangeOfSpacingAfterSlashes = Range(match.range(at: 1), in: toolsVersionSpecificationString),
              let rangeOfVersionSpecifier = Range(match.range(at: 2), in: toolsVersionSpecificationString) else {
            fatalError("failed to initialise instances of Range<String.Index> from valid regex match ranges")
        }
        
        /// The horizontal spacing between "//" and  "swift-tools-version".
        let spacingAfterSlashes = toolsVersionSpecificationString[rangeOfSpacingAfterSlashes]
        /// The version number specifier.
        let versionSpecifier = toolsVersionSpecificationString[rangeOfVersionSpecifier]
        
        return ManifestComponents(
            leadingLineTerminators: leadingLineTerminators,
            toolsVersionSpecification: toolsVersionSpecification,
            contentsAfterToolsVersionSpecification: manifestContentsAfterToolsVersionSpecification,
            toolsVersionSpecificationCapturedComponents: ToolsVersionSpecificationCapturedComponents(
                spacingAfterSlashes: spacingAfterSlashes,
                versionSpecifier: versionSpecifier
            )
        )
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
