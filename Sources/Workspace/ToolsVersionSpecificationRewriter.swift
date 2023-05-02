//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// -----------------------------------------------------------------------------
///
/// This file implements a global function that rewrite the Swift tools version specification of a manifest file.
///
// -----------------------------------------------------------------------------

import Basics
import PackageModel
import PackageLoading

import struct TSCBasic.ByteString
import class TSCBasic.BufferedOutputByteStream

public struct ToolsVersionSpecificationWriter {
    // designed to be used as a static utility
    private init() {}

    /// Rewrites Swift tools version specification to the non-version-specific manifest file (`Package.swift`) in the given directory.
    ///
    /// If the main manifest file already contains a valid tools version specification (ignoring the validity of the version specifier and that of everything following it), then the existing specification is replaced by this new one.
    ///
    /// The version specifier in the specification does not contain any build metadata or pre-release identifier. The patch version is included if and only if it's not zero.
    ///
    /// A `FileSystemError` is thrown if the manifest file is unable to be read from or written to.
    ///
    /// - Precondition: `manifestDirectoryPath` must be a valid path to a directory that contains a `Package.swift` file.
    ///
    /// - Parameters:
    ///   - manifestDirectory: The absolute path to the given directory.
    ///   - toolsVersion: The Swift tools version to specify as the lowest supported version.
    ///   - fileSystem: The filesystem to read/write the manifest file on.
    public static func rewriteSpecification(manifestDirectory: AbsolutePath, toolsVersion: ToolsVersion, fileSystem: FileSystem) throws {
        let manifestFilePath = manifestDirectory.appending(component: Manifest.filename)

        guard fileSystem.isFile(manifestFilePath) else {
            guard fileSystem.exists(manifestFilePath) else {
                throw ManifestAccessError(.noSuchFileOrDirectory, at: manifestFilePath)
            }
            guard !fileSystem.isDirectory(manifestFilePath) else {
                throw ManifestAccessError(.isADirectory, at: manifestFilePath)
            }
            throw ManifestAccessError(.unknown, at: manifestFilePath)
        }

        /// The current contents of the file.
        let contents = try fileSystem.readFileContents(manifestFilePath)

        let stream = BufferedOutputByteStream()
        // Write out the tools version specification, including the patch version if and only if it's not zero.
        stream.send("\(toolsVersion.specification(roundedTo: .automatic))\n")

        // The following lines up to line 77 append the file contents except for the Swift tools version specification line.

        guard let contentsDecodedWithUTF8 = contents.validDescription else {
            throw ToolsVersionParser.Error.nonUTF8EncodedManifest(path: manifestFilePath)
        }

        let manifestComponents = ToolsVersionParser.split(contentsDecodedWithUTF8)

        let toolsVersionSpecificationComponents = manifestComponents.toolsVersionSpecificationComponents

        // Replace the Swift tools version specification line if and only if it's well-formed up to the version specifier.
        // This matches the behavior of the old (now removed) [`ToolsVersionLoader.split(:_)`](https://github.com/WowbaggersLiquidLunch/swift-package-manager/blob/49cfc46bc5defd3ce8e0c0261e3e2cb475bcdb91/Sources/PackageLoading/ToolsVersionLoader.swift#L160).
        if toolsVersionSpecificationComponents.everythingUpToVersionSpecifierIsWellFormed {
            stream.send(String(manifestComponents.contentsAfterToolsVersionSpecification))
        } else {
            stream.send(contents)
        }

        try fileSystem.writeFileContents(manifestFilePath, bytes: stream.bytes)
    }

    /// An error that causes the access to a manifest to fails.
    struct ManifestAccessError: Error, CustomStringConvertible {
        public init(_ kind: Kind, at path: AbsolutePath) {
            self.kind = kind
            self.path = path
        }

        /// The kind of the error being raised.
        public enum Kind: Equatable {
            /// A component of a specified pathname did not exist, or the pathname was an empty string.
            ///
            /// This error is equivalent to `TSCBasic.FileSystemError.Kind.noEntry` and corresponds to the POSIX ENOENT error code, but is specialised for manifest access.
            case noSuchFileOrDirectory
            /// The path points to a directory.
            ///
            /// This error is equivalent to `TSCBasic.FileSystemError.Kind.isDirectory` and corresponds to rhe POSIX EISDIR error code, but is specialised for manifest access.
            case isADirectory
            /// The manifest cannot be accessed for an unknown reason.
            case unknown
        }

        /// The kind of the error being raised.
        public let kind: Kind

        /// The absolute path where the error occurred.
        public let path: AbsolutePath

        public var description: String {
            var reason: String {
                switch kind {
                case .noSuchFileOrDirectory:
                    return "a component of the path does not exist, or the path is an empty string"
                case .isADirectory:
                    return "the path is a directory; a file is expected"
                case .unknown:
                    return "an unknown error occurred"
                }
            }
            return "no accessible Swift Package Manager manifest file found at '\(path)'; \(reason)"
        }
    }
}
