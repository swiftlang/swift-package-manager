/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
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
    // Relevant discussion: https://github.com/apple/swift-package-manager/pull/2937#discussion_r512239726
    /// The Swift toolchain version used by the instance of `ToolsVersionLoader`.
    ///
    /// If the value differs from `ToolsVersion.currentToolsVersion`, then the `ToolsVersionLoader` instance is simulating that it's run on a Swift version different from the version used by libSwiftPM.
    let currentToolsVersion: ToolsVersion
    
    /// Creates a manifest loader with the given Swift toolchain version.
    /// - Parameter currentToolsVersion: The Swift toolchain version to simulate the manifest loading strategy for. By default, this parameter is the current version used by libSwiftPM. A non-default version is only used for providing testability.
    public init(currentToolsVersion: ToolsVersion = .currentToolsVersion) {
        self.currentToolsVersion = currentToolsVersion
    }

    // Parameter names for associated values help the auto-complete provide hints at the call site, even when the argument label is suppressed.
    
    // FIXME: Use generic associated type `T: StringProtocol` instead of concrete types `String` and `Substring`, when/if this feature comes to Swift.
    public enum Error: Swift.Error, CustomStringConvertible {
        
        /// Location of the tools version specification's malformation.
        public enum ToolsVersionSpecificationMalformationLocation {
            /// The nature of malformation at the location in Swift tools version specification.
            public enum MalformationDetails {
                /// The Swift tools version specification component is missing.
                case isMissing
                /// The Swift tools version specification component is misspelt.
                case isMisspelt(_ misspelling: String)
            }
            /// The comment marker is malformed.
            ///
            /// If the comment marker is missing, it could be an indication that the entire Swift tools version specification is missing.
            case commentMarker(_ malformationDetails: MalformationDetails)
            /// The label part of the Swift tools version specification is malformed.
            case label(_ malformationDetails: MalformationDetails)
            /// The version specifier is malformed.
            case versionSpecifier(_ malformationDetails: MalformationDetails)
        }
        
        /// Details of backward-incompatible contents with Swift tools version ≤ 5.3.
        ///
        /// A backward-incompatibility is not necessarily a malformation.
        public enum BackwardIncompatibilityPre5_3_1 {
            /// The whitespace at the start of the manifest is not all `U+000A`.
            case leadingWhitespace(_ whitespace: String)
            /// The horizontal spacing between "//" and  "swift-tools-version" either is empty or uses whitespace characters unsupported by Swift ≤ 5.3.
            case spacingAfterCommentMarker(_ spacing: String)
            /// There is a non-empty spacing between the label part of the Swift tools version specification and the version specifier.
            case spacingAfterLabel(_ spacing: String)
        }
        
        /// Package directory is inaccessible (missing, unreadable, etc).
        case inaccessiblePackage(path: AbsolutePath, reason: String)
        /// Package manifest file is inaccessible (missing, unreadable, etc).
        case inaccessibleManifest(path: AbsolutePath, reason: String)
        /// Package manifest file's content can not be decoded as a UTF-8 string.
        case nonUTF8EncodedManifest(path: AbsolutePath)
        /// Malformed tools version specification.
        case malformedToolsVersionSpecification(_ malformationLocation: ToolsVersionSpecificationMalformationLocation)
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
            case let .malformedToolsVersionSpecification(malformationLocation):
                switch malformationLocation {
                case let .commentMarker(malformationDetails):
                    switch malformationDetails {
                    case .isMissing:
                        return "the manifest is missing a Swift tools version specification; consider prepending to the manifest '// swift-tools-version:\(ToolsVersion.currentToolsVersion)' to specify the current Swift toolchain version as the lowest supported version by the project; if such a specification already exists, consider moving it to the top of the manifest, or prepending it with '//' to help Swift Package Manager find it"
                    case .isMisspelt(let misspeltCommentMarker):
                        return "the comment marker '\(misspeltCommentMarker)' is misspelt for the Swift tools version specification; consider replacing it with '//'"
                    }
                case let .label(malformationDetails):
                    switch malformationDetails {
                    case .isMissing:
                        return "the Swift tools version specification is missing a label; consider inserting 'swift-tools-version:' between the comment marker and the version specifier"
                    case .isMisspelt(let misspeltLabel):
                        return "the Swift tools version specification's label '\(misspeltLabel)' is misspelt; consider replacing it with 'swift-tools-version:'"
                    }
                case let .versionSpecifier(malformationDetails):
                    switch malformationDetails {
                    case .isMissing:
                        // If the version specifier is missing, then its terminator must be missing as well. So, there is nothing in between the version specifier and everything that should be in front the version specifier. So, appending a valid version specifier will fix this error.
                        return "the Swift tools version specification is missing a version specifier; consider appending '\(ToolsVersion.currentToolsVersion)' to the line to specify the current Swift toolchain version as the lowest supported version by the project"
                    case .isMisspelt(let misspeltVersionSpecifier):
                        return "the Swift tools version '\(misspeltVersionSpecifier)' is misspelt or otherwise invalid; consider replacing it with '\(ToolsVersion.currentToolsVersion)' to specify the current Swift toolchain version as the lowest supported version by the project"
                    }
                }
            case let .backwardIncompatiblePre5_3_1(incompatibility, specifiedVersion):
                switch incompatibility {
                case let .leadingWhitespace(whitespace):
                    return "leading whitespace sequence \(unicodeCodePointsPrefixedByUPlus(of: whitespace)) in manifest is supported by only Swift > 5.3; the specified version \(specifiedVersion) supports only newline characters (U+000A) preceding the Swift tools version specification; consider moving the Swift tools version specification to the first line of the manifest"
                case let .spacingAfterCommentMarker(spacing):
                    return "\(spacing.isEmpty ? "zero spacing" : "horizontal whitespace sequence \(unicodeCodePointsPrefixedByUPlus(of: spacing))") between '//' and 'swift-tools-version' is supported by only Swift > 5.3; consider replacing the sequence with a single space (U+0020) for Swift \(specifiedVersion)"
                case let .spacingAfterLabel(spacing):
                    return "horizontal whitespace sequence \(unicodeCodePointsPrefixedByUPlus(of: spacing)) immediately preceding the version specifier is supported by only Swift > 5.3; consider removing the sequence for Swift \(specifiedVersion)"
                }
            }
            
        }
    }
    
    /// A representation of a manifest in its constituent parts.
    public struct ManifestComponents {
        /// The largest contiguous sequence of whitespace characters at the very beginning of the manifest.
        public let leadingWhitespace: Substring
        /// The Swift tools version specification represented in its constituent parts.
        public let toolsVersionSpecificationComponents: ToolsVersionSpecificationComponents
        /// The remaining contents of the manifest that follows right after the tools version specification line.
        public let contentsAfterToolsVersionSpecification: Substring
        /// A Boolean value indicating whether the manifest represented in its constituent parts is backward-compatible with Swift ≤ 5.3.
        public var isCompatibleWithPreSwift5_3_1: Bool {
            leadingWhitespace.allSatisfy { $0 == "\n" } && toolsVersionSpecificationComponents.isCompatibleWithPreSwift5_3_1
        }
    }
    
    /// A representation of a Swift tools version specification in its constituent parts.
    ///
    /// A Swift tools version specification consists of the following parts:
    ///
    ///     //  swift-tools-version:  5.3.1
    ///     ⌃~⌃~⌃~~~~~~~~~~~~~~~~~~~⌃~⌃~~~~
    ///     │ │ └ label             │ └ version specifier
    ///     │ └ spacing             └ spacing
    ///     └ comment marker
    ///
    public struct ToolsVersionSpecificationComponents {
        /// The comment marker.
        ///
        /// In a well-formed Swift tools version specification, the comment marker is `"//"`.
        public let commentMarker: Substring
        
        /// The spacing after the comment marker
        ///
        /// In a well-formed Swift tools version specification, the spacing after the comment marker is a continuous sequence of horizontal whitespace characters.
        ///
        /// For Swift ≤ 5.3, the spacing after the comment marker must be a single `U+0020`.
        public let spacingAfterCommentMarker: Substring
        
        /// The label part of the Swift tools version specification.
        ///
        /// In a well-formed Swift tools version specification, the label is `"swift-tools-version:"`
        public let label: Substring
        
        /// The spacing between the label part of the Swift tools version specification and the version specifier.
        ///
        /// In a well-formed Swift tools version specification, the spacing after the label is a continuous sequence of horizontal whitespace characters.
        ///
        /// For Swift ≤ 5.3, no spacing is allowed after the label.
        public let spacingAfterLabel: Substring
        
        /// The version specifier.
        public let versionSpecifier: Substring
        
        /// A Boolean value indicating whether everything up to the version specifier in the Swift tools version specification represented in its constituent parts is well-formed.
        public var everythingUpToVersionSpecifierIsWellFormed: Bool {
            // FIXME: Make `label` case sensitive?
            // FIXME: Replace with `commentMarker == "//" && (label == "swift-tools-version:" || label.lowercased() == "swift-tools-version:")`?
            // "swift-tools-version:" has more than 15 UTF-8 code units, so `label` is likely to have more than 15 UTF-8 code units too.
            // Strings with more than 15 UTF-8 code units are heap-allocated on 64-bit platforms, 10 on 32-bit platforms.
            // `lowercase()` returns a heap-allocated string here, and this is inefficient, although the inefficiency is perhaps insignificant.
            // Short-circuiting the `lowercase()` can remove an allocation.
            commentMarker == "//" && label.lowercased() == "swift-tools-version:"
        }
        
        /// A Boolean value indicating whether the Swift tools version specification represented in its constituent parts is backward-compatible with Swift ≤ 5.3.
        public var isCompatibleWithPreSwift5_3_1: Bool {
            everythingUpToVersionSpecifierIsWellFormed && spacingAfterCommentMarker == "\u{20}" && spacingAfterLabel.isEmpty
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

    // FIXME: Using "file" as the parameter name (and label) sounds wrong in some subsequent use of it in the function body.
    // Maybe rename the function as `fileprivate func load(fileAt filePath: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion`?
    fileprivate func load(file: AbsolutePath, fileSystem: FileSystem) throws -> ToolsVersion {
        // FIXME: We don't need the entire file, just the first line.
        let manifestContents: ByteString
        do { manifestContents = try fileSystem.readFileContents(file) } catch {
            throw Error.inaccessibleManifest(path: file, reason: String(describing: error))
        }
        
        // FIXME: This is doubly inefficient.
        // `contents`'s value comes from `FileSystem.readFileContents(_)`, which is [inefficient](https://github.com/apple/swift-tools-support-core/blob/8f9838e5d4fefa0e12267a1ff87d67c40c6d4214/Sources/TSCBasic/FileSystem.swift#L167). Calling `ByteString.validDescription` on `contents` is also [inefficient, and possibly incorrect](https://github.com/apple/swift-tools-support-core/blob/8f9838e5d4fefa0e12267a1ff87d67c40c6d4214/Sources/TSCBasic/ByteString.swift#L121). However, this is a one-time thing for each package manifest, and almost necessary in order to work with all Unicode line-terminators. We probably can improve its efficiency and correctness by using `URL` for the file's path, and get is content via `Foundation.String(contentsOf:encoding:)`. Swift System's [`FilePath`](https://github.com/apple/swift-system/blob/8ffa04c0a0592e6f4f9c30926dedd8fa1c5371f9/Sources/System/FilePath.swift) and friends might help as well.
        // This is source-breaking.
        // A manifest that has an [invalid byte sequence](https://en.wikipedia.org/wiki/UTF-8#Invalid_sequences_and_error_handling) (such as `0x7F8F`) after the tools version specification line could work in Swift ≤ 5.3, but results in an error since Swift 5.3.1.
        guard let manifestContentsDecodedWithUTF8 = manifestContents.validDescription else {
            throw Error.nonUTF8EncodedManifest(path: file)
        }
        
        /// The manifest represented in its constituent parts.
        let manifestComponents = ToolsVersionLoader.split(manifestContentsDecodedWithUTF8)
        /// The Swift tools version specification represented in its constituent parts.
        let toolsVersionSpecificationComponents = manifestComponents.toolsVersionSpecificationComponents
        
        // The diagnosis of the manifest's formatting's correctness goes in the following order:
        //
        // 1. Check that the comment marker, the label, and the version specifier in the Swift tools version specification are not missing (empty).
        //
        // 2. Check that everything in the Swift tools version specification up to the version specifier is formatted correctly according to the relaxed rules since Swift 5.3.1. Backward-compatibility is not considered here, because the user-specified version is unknown yet.
        //
        //    1. Check that the comment marker is formatted correctly.
        //
        //    2. Check that the label is formatted correctly
        //
        //    3. Check that there is no unforeseen formatting error in the Swift tools version specification up to the version specifier.
        //
        // 3. Check that the version spicier is formatted correctly.
        //
        // 4. Check that the manifest is formatted backward-compatibly, if the user-specified version is ≤ 5.3. Backward-compatibility checks are now possible, because the user-specified version has become known since the previous step.
        //
        //    1. Check that the manifest's leading whitespace is backward-compatible with Swift ≤ 5.3.
        //
        //    2. Check that the spacing after the comment marker in the Swift tools version specification is backward-compatible with Swift ≤ 5.3.
        //
        //    3. Check that the spacing after the label in the Swift tools version specification is backward-compatible with Swift ≤ 5.3.
        //
        // This order is based on the general idea that a manifest's readability should come before its validity when being diagnosed. The package manager must first understand what is written in the manifest before it can tell if anything is wrong. This idea is manifested (no pun intended) in 2 areas of the diagnosis process:
        //
        // 1. The version specifier contains the most important piece of information, but it's checked last in the Swift tools version specification. This happens twice: both in checking its existence and in checking its correctness.
        //
        //    This is because the package manager must be confident that the version specifier it sees is exactly what the user has provided, not polluted by anything that comes before it. With English written left-to-right, and the manifest parsed largely left-to-right, errors in the comment marker and the label could be mistaken by the package manager as the version specifier's. Consider the following Swift tools version specification, where an "l" is mistyped with "1":
        //
        //        // swift-too1s-version: 5.3
        //
        //    Were the version specifier checked before everything else, the package manager will mistake "1s-version: 5.3" as the version specifier, treating the typo in the label as an error in the version specifier. The user will likely be confused, when informed by the diagnostics message that the version specifier is misspelt.
        //
        //    With the label checked before the version specifier, the diagnosis can be more precise, and this kind of confusion to the user can be avoided.
        //
        // 2. Backward-compatibility checks of the manifest are after the formatting checks of the Swift tools version specification, not during them.
        //
        //    Although it makes more sense, form a human's perspective, if the backward-compatibility checks is integrated within the formatting checks, the package manager can not see things as holistically as a human does. It can not pinpoint all errors in the manifest simultaneously, or understand the user's intention when the manifest has formatting errors, let alone finding any backward-incompatibility. It is better to first ensure that the manifest is formatted correctly according to the latest rules, then compare it against old rules to find backward-incompatibilities.
        
        let commentMarker = toolsVersionSpecificationComponents.commentMarker
        guard !commentMarker.isEmpty else {
            throw Error.malformedToolsVersionSpecification(.commentMarker(.isMissing))
        }
        
        let label = toolsVersionSpecificationComponents.label
        guard !label.isEmpty else {
            throw Error.malformedToolsVersionSpecification(.label(.isMissing))
        }
        
        let versionSpecifier = toolsVersionSpecificationComponents.versionSpecifier
        guard !versionSpecifier.isEmpty else {
            throw Error.malformedToolsVersionSpecification(.versionSpecifier(.isMissing))
        }
        
        guard toolsVersionSpecificationComponents.everythingUpToVersionSpecifierIsWellFormed else {
            if commentMarker != "//" {
                throw Error.malformedToolsVersionSpecification(.commentMarker(.isMisspelt(String(commentMarker))))
            }
            
            if label.lowercased() != "swift-tools-version:" {
                throw Error.malformedToolsVersionSpecification(.label(.isMisspelt(String(label))))
            }
            
            // The above If-statements should have covered all possible malformations in Swift tools version specification up to the version specifier.
            // If you changed the logic in this file, and this fatal error is triggered, then you need to re-check the logic, and make sure all possible error conditions are covered in the Else-block.
            fatalError("unidentified malformation in the Swift tools version specification")
        }
        
        guard let version = ToolsVersion(string: String(versionSpecifier)) else {
            throw Error.malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt(String(versionSpecifier))))
        }
        
        guard version > .v5_3 || manifestComponents.isCompatibleWithPreSwift5_3_1 else {
            let manifestLeadingWhitespace = manifestComponents.leadingWhitespace
            if !manifestLeadingWhitespace.allSatisfy({ $0 == "\n" }) {
                throw Error.backwardIncompatiblePre5_3_1(.leadingWhitespace(String(manifestLeadingWhitespace)), specifiedVersion: version)
            }
            
            let spacingAfterCommentMarker = toolsVersionSpecificationComponents.spacingAfterCommentMarker
            if spacingAfterCommentMarker != "\u{20}" {
                throw Error.backwardIncompatiblePre5_3_1(.spacingAfterCommentMarker(String(spacingAfterCommentMarker)), specifiedVersion: version)
            }
            
            let spacingAfterLabel = toolsVersionSpecificationComponents.spacingAfterLabel
            if !spacingAfterLabel.isEmpty {
                throw Error.backwardIncompatiblePre5_3_1(.spacingAfterLabel(String(spacingAfterLabel)), specifiedVersion: version)
            }
            
            // The above If-statements should have covered all possible backward incompatibilities with Swift ≤ 5.3.
            // If you changed the logic in this file, and this fatal error is triggered, then you need to re-check the logic, and make sure all possible error conditions are covered in the Else-block.
            fatalError("unidentified backward-incompatibility with Swift ≤ 5.3 in the manifest")
        }
        
        return version
    }
    
    // FIXME: Remove this function.
    // This function is currently preserved because it's used in `writeToolsVersion(at:version:fs:).
    /// Splits the bytes to find the Swift tools version specifier and the contents sans the first line of the manifest.
    ///
    /// - Warning: This function has been deprecated since Swift 5.3.1, please use `split(_ manifestContents: String) -> ManifestComponents` instead.
    ///
    /// - Note: This function imposes the following limitations that are removed in its replacement:
    ///   - Leading whitespace, other than a sequence of newline characters (`U+000A`), is not accepted in the given manifest contents.
    ///   - Only `U+000A` is recognised as a line terminator.
    ///   - A Swift tools version specification must be prefixed with `// swift-tools-version:` verbatim, where the spacing between `//` and `swift-tools-version` is exactly 1 `U+0020`.
    ///
    /// - Bug: This function treats only `U+000A` as a line terminator.
    /// - Bug: If there is a contiguous sequence of `U+000A` at the very beginning of the manifest file, this function mistakes the first non-empty line of the manifest as its first line.
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
              // The 2 ranges are:
              //   1. The entire matched string.
              //   2. Capture group 1: The version specifier.
              // Since the version specifier is in the last range, if the number of ranges is less than 2, then no version specifier is captured by the regex.
              // FIXME: Should this be `== 2` instead?
              match.numberOfRanges >= 2 else {
            return (nil, bytes.contents)
        }
        let versionSpecifier = NSString(string: firstLine).substring(with: match.range(at: 1))
        // FIXME: We can probably optimize here and return array slice.
        return (versionSpecifier, splitted.count == 1 ? [] : Array(splitted[1]))
    }
    
    /// Splits the given manifest into its constituent components.
    ///
    /// A manifest consists of the following parts:
    ///
    ///                                                      ⎫
    ///                                                      ⎪
    ///                                                      ⎬ leading whitespace-only lines
    ///                                                      ⎪
    ///                                                      ⎭
    ///       ┌ Swift tools version specification
    ///       │                              ┌ ignored trailing contents
    ///       ⌄~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~⌄~~~~~~~~~~
    ///       //  swift-tools-version:  5.3.1;2020-09-16     } the Swift tools version specification line
    ///     ⌃~⌃~⌃~⌃~~~~~~~~~~~~~~~~~~~⌃~⌃~~~~⌃⌃~~~~~~~~~
    ///     │ │ │ └ label             │ │    │└ trailing comment segment including a trailing line terminator, if any (not returned by this function)
    ///     │ │ └ spacing             │ │    └ specification terminator (not returned by this function)
    ///     │ └ comment marker        │ └ version specifier
    ///     │                         └ spacing
    ///     └ additional leading whitespace
    ///                                                      ⎫
    ///                                                      ┇
    ///                                                      ⎬ the rest of the manifest's contents
    ///                                                      ┇
    ///                                                      ⎭
    ///
    /// - Note: The splitting mostly assumes that the manifest is well-formed. A malformed component may lead to incorrect identification of other components.
    ///
    ///   For example, a malformed Swift tools version specification `"// swift-too1s-version:5.3"` misleads this function to identify `"swift-too"` as the label, and `"1s-version:5.3"` the version specifier.
    ///
    /// - Parameter manifest: The UTF-8-encoded content of the manifest.
    /// - Returns: The components of the given manifest.
    public static func split(_ manifest: String) -> ManifestComponents {
        
        // We split the string manually instead of using `Collection.split(maxSplits:omittingEmptySubsequences:whereSeparator:)`, because the latter "strips" leading and trailing whitespace, and we need to record the leading whitespace to check for backward-compatibility later.
        
        /// The position of the first character of the Swift tools version specification line in the manifest.
        ///
        /// Because the tools version specification line is the first non-whitespace-only line in the manifest, the position of its first character is also the position of the first non-whitespace character in the manifest. If there is only whitespace in the manifest, then this position is the `endIndex` of the manifest.
        let startIndexOfSpecification = manifest.firstIndex(where: { !$0.isWhitespace } ) ?? manifest.endIndex
        
        /// The whitespace at the start of the manifest.
        ///
        /// Because the tools version specification is the first non-whitespace-only character sequence in the manifest, the manifest's leading whitespace are the only characters in front of the tools version specification.
        let leadingWhitespace = manifest[..<startIndexOfSpecification]
        
        /// The position right past the last character of the Swift tools version specification line in the manifest.
        ///
        /// Because the specification line ends at a line terminator, the position right past the line's last character is the position of the terminator of the line. If no such line terminator exists, then this position is the `endIndex` of the manifest.
        let endIndexOfSpecificationLine = manifest[startIndexOfSpecification...].firstIndex(where: \.isNewline) ?? manifest.endIndex
        
        /// The Swift tools version specification with ignored trailing contents.
        ///
        /// The specification is the first comment (until its terminator) in the manifest that declares the version of the `PackageDescription` library, the minimum version of the Swift tools and Swift language compatibility version to process the manifest, and the minimum version of the Swift tools that are needed to use the Swift package.
        ///
        /// The ignored trailing contents are everything starting from the first semicolon after the version specifier in the line.
        let specificationWithIgnoredTrailingContents = manifest[startIndexOfSpecification..<endIndexOfSpecificationLine]
        
        /// The position right past the last character of the Swift tools version specification's comment marker.
        ///
        /// This is the same as the position of the first character that is neither `"/"` nor `"*"` in the Swift tools version specification. If no such character exists, then this position is the `endIndex` of the Swift tools version specification.
        let endIndexOfCommentMarker = specificationWithIgnoredTrailingContents.firstIndex(where: { $0 != "/" && $0 != "*" } ) ?? specificationWithIgnoredTrailingContents.endIndex
        
        /// The comment marker of the Swift tools version specification.
        ///
        /// The continuous sequence of `"/"`s and `"*"`s immediately following the leading whitespace is considered as the comment marker, regardless of its validity.
        let commentMarker = specificationWithIgnoredTrailingContents[..<endIndexOfCommentMarker]
        
        /// The position right past the last character of the spacing that immediately follows the comment marker.
        ///
        /// Because the spacing consists of only horizontal whitespace characters, this position is the same as the first character that's not a horizontal whitespace after `commentMarker`. If no such character exists, then the position is the `endIndex` of the Swift tools version specification line.
        let endIndexOfSpacingAfterCommentMarker = specificationWithIgnoredTrailingContents[endIndexOfCommentMarker...].firstIndex(where: { !$0.isWhitespace } ) ?? specificationWithIgnoredTrailingContents.endIndex
        //                                                                                                                                    ☝️
        // Technically, this is looking for the position of the first character that's not a whitespace, BOTH HORIZONTAL AND VERTICAL. However, since all vertical horizontal whitespace characters are also line terminators, and because the Swift tools version specification does not contain any line terminator, we can safely use `Character.isWhitespace` to check if a character is a horizontal whitespace.
        
        /// The spacing that immediately follows `commentMarker`.
        ///
        /// The spacing consists of only horizontal whitespace characters.
        let spacingAfterCommentMarker = specificationWithIgnoredTrailingContents[endIndexOfCommentMarker..<endIndexOfSpacingAfterCommentMarker]
        
        // FIXME: Use `CharacterSet.decimalDigits` instead?
        // `Character.isNumber` is true for more than just decimal characters (e.g. ㊅ and 𝟘), but `CharacterSet.contains(_:)` works only on Unicode scalars.
        /// The position of the first character in the version specifier.
        ///
        /// Because a version specifier starts with a numeric character, and because only the version specifier is expected to have numeric characters, this position is the same as the position of the first numeric character in the Swift tools version specification line. If no such character exists, then this position is the `endIndex` of the line.
        ///
        /// - Note: For a misspelt Swift tools version specification `"// swift-too1s-version:5.3"`, the first `"1"` is considered as the first character of the version specifier, and so `"1s-version:5.3"` is taken as the version specifier.
        let startIndexOfVersionSpecifier = specificationWithIgnoredTrailingContents[endIndexOfSpacingAfterCommentMarker...].firstIndex(where: \.isNumber) ?? specificationWithIgnoredTrailingContents.endIndex
        //                                                                         ☝️
        // We know for sure that there is no numeric characters before `endIndexOfSpacingAfterCommentMarker`, so `specificationWithIgnoredTrailingContents[endIndexOfSpacingAfterCommentMarker...]` saves a bit of unnecessary searching.
        
        /// The label part of the Swift tools version specification with the whitespace sequence between the label and the version specifier.
        /// - Note: For a misspelt Swift tools version specification `"// swift-too1s-version: 5.3.1"`, the label stops at the second `"o"`, so only `"swift-too"` is recognised as the label with no spacing following it.
        let labelWithTrailingWhitespace = specificationWithIgnoredTrailingContents[endIndexOfSpacingAfterCommentMarker..<startIndexOfVersionSpecifier]
        
        /// The position of the first character in the spacing after the label part of the Swift tools version specification.
        ///
        /// Because there is no whitespace within the label, and because the spacing consists of only horizontal whitespace characters, so this position is the same as the position of the first whitespace character between the beginning of the label and the beginning of the version specifier. If no such whitespace character exists, then there is no spacing, and so this position is the `endIndex` of these sequence of characters (i.e. the starting position of the version specifier).
        let startIndexOfSpacingAfterLabel = labelWithTrailingWhitespace.firstIndex(where: \.isWhitespace) ?? startIndexOfVersionSpecifier
        
        /// The label part of the Swift tools version specification.
        /// - Note: For a misspelt Swift tools version specification `"// swift-too1s-version: 5.3.1"`, the label stops at the second `"o"`, so only `"swift-too"` is recognised as the label.
        let label = labelWithTrailingWhitespace[..<startIndexOfSpacingAfterLabel]
        
        /// The spacing between the label part of the Swift tools version specification and the version specifier.
        /// - Note: For a misspelt Swift tools version specification `"// swift-too1s-version: 5.3.1"`, the label stops at the second `"o"`, and the version specifier starts from the first `"1"`, so no spacing is recognised.
        let spacingAfterLabel = labelWithTrailingWhitespace[startIndexOfSpacingAfterLabel...]
        
        /// The position of the version specifier's terminator.
        ///
        /// The terminator can be either a `";"` or a line terminator. If no such character exists, then this position is the `endIndex` of the Swift tools version specification.
        let indexOfVersionSpecifierTerminator = specificationWithIgnoredTrailingContents[startIndexOfVersionSpecifier...].firstIndex(where: { $0 == ";" } ) ?? specificationWithIgnoredTrailingContents.endIndex
        //                                                                                                                                          ☝️
        // Technically, this is looking for the position of the first ";" only, not the first line terminator. However, because the Swift tools version specification does not contain any line terminator, we can safely search just the first ";".
        
        // The version specifier and its terminator together are first found by locating the first numeric character in the specification line, and the version specifier starts with that first numeric character. So, if the version specifier is empty, then the line has no numeric characters, then the specification's ignored trailing contents are empty too. Basically, if the version specifier is empty, then the specification has no ignored trailing contents.
        
        /// The version specifier.
        /// - Note: For a misspelt Swift tools version specification `"// swift-too1s-version:5.3"`, the first `"1"` is considered as the first character of the version specifier, and so `"1s-version:5.3"` is taken as the version specifier.
        let versionSpecifier = specificationWithIgnoredTrailingContents[startIndexOfVersionSpecifier..<indexOfVersionSpecifierTerminator]
        
        // The tertiary condition checks if the specification line's end index is the same as the manifest's.
        // If it is, then just use the index, because the rest of the manifest is empty, and because using `index(after:)` on it results in an index-out-of-bound error.
        /// The position of the first character following the tools version specification line in the manifest.
        ///
        /// If no such character exists, then the position is the `endIndex` of the manifest.
        let startIndexOfManifestAfterSpecification = endIndexOfSpecificationLine == manifest.endIndex ? manifest.endIndex : manifest.index(after: endIndexOfSpecificationLine)
        
        /// The remaining contents of the manifest that follows right after the tools version specification line.
        let manifestAfterSpecification = manifest[startIndexOfManifestAfterSpecification...]
        
        return ManifestComponents(
            leadingWhitespace: leadingWhitespace,
            toolsVersionSpecificationComponents: ToolsVersionSpecificationComponents(
                commentMarker: commentMarker,
                spacingAfterCommentMarker: spacingAfterCommentMarker,
                label: label,
                spacingAfterLabel: spacingAfterLabel,
                versionSpecifier: versionSpecifier
            ),
            contentsAfterToolsVersionSpecification: manifestAfterSpecification
        )
    }
    
    // This property is preserved only because of the old `split(_:)`.
    // When the old `split(_:)` is removed, this should be removed too.
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
    @available(swift, deprecated: 5.3.1)
    static let regex = try! NSRegularExpression(
        pattern: "^// swift-tools-version:(.*?)(?:;.*|$)",
        options: [.caseInsensitive])
}
