//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import struct Foundation.Data

public enum ManifestSignatureParser {
    public static func parse(manifestPath: AbsolutePath, fileSystem: FileSystem) throws -> ManifestSignature? {
        let manifestContents: String
        do {
            manifestContents = try fileSystem.readFileContents(manifestPath)
        } catch {
            throw Error.inaccessibleManifest(path: manifestPath, reason: String(describing: error))
        }
        return try self.parse(utf8String: manifestContents)
    }

    public static func parse(utf8String: String) throws -> ManifestSignature? {
        let manifestComponents = Self.split(utf8String)

        guard let signatureComponents = manifestComponents.signatureComponents else {
            return .none
        }

        guard let signature = Data(base64Encoded: String(signatureComponents.signatureBase64Encoded)) else {
            throw Error.malformedManifestSignature
        }

        return ManifestSignature(
            contents: Array(String(manifestComponents.contentsBeforeSignatureComponents).utf8),
            signatureFormat: String(signatureComponents.signatureFormat),
            signature: Array(signature)
        )
    }

    /// Splits the given manifest into its constituent components.
    ///
    /// A **signed** manifest consists of the following parts:
    ///
    ///                                                    ⎫
    ///                                                    ┇
    ///                                                    ⎬ manifest's contents (returned by this function)
    ///                                                    ┇
    ///                                                    ⎭
    ///       ┌ manifest signature
    ///       ⌄~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///       //  signature:  cms-1.0.0;MIIFujCCBKKgAw...  } the manifest signature line
    ///     ⌃~⌃~⌃~⌃~~~~~~~~~⌃~⌃~~~~~~~~^^~~~~~~~~~~~~~~~~
    ///     | | | |         | |        |└ signature base64-encoded (returned by this function)
    ///     | │ │ └ label   │ |        └ signature format terminator
    ///     | | |           | └ signature format (returned by this function)
    ///     | │ └ spacing   └ spacing
    ///     | └ comment marker
    ///     └ additional leading whitespace
    ///
    /// - Parameter manifest: The UTF-8-encoded content of the manifest.
    /// - Returns: The components of the given manifest.
    private static func split(_ manifest: String) -> ManifestComponents {
        // The signature, if any, is the last line in the manifest.
        let endIndexOfSignatureLine = manifest.lastIndex(where: { !$0.isWhitespace }) ?? manifest.endIndex
        let endIndexOfManifestContents = manifest[..<endIndexOfSignatureLine]
            .lastIndex(where: { $0.isNewline }) ?? manifest.endIndex
        let startIndexOfCommentMarker = manifest[endIndexOfManifestContents...]
            .firstIndex(where: { $0 == "/" }) ?? manifest.endIndex

        // There doesn't seem to be a signature, return manifest as-is.
        guard startIndexOfCommentMarker < endIndexOfSignatureLine else {
            return ManifestComponents(contentsBeforeSignatureComponents: manifest[...], signatureComponents: .none)
        }

        let endIndexOfCommentMarker = manifest[startIndexOfCommentMarker...]
            .firstIndex(where: { $0 != "/" }) ?? manifest.endIndex

        let startIndexOfLabel = manifest[endIndexOfCommentMarker...].firstIndex(where: { !$0.isWhitespace }) ?? manifest
            .endIndex
        let endIndexOfLabel = manifest[startIndexOfLabel...].firstIndex(where: { $0 == ":" }) ?? manifest.endIndex

        // Missing "signature:" label, assume there is no signature.
        guard startIndexOfLabel < endIndexOfLabel,
              String(manifest[startIndexOfLabel ..< endIndexOfLabel]).lowercased() == "signature"
        else {
            return ManifestComponents(contentsBeforeSignatureComponents: manifest[...], signatureComponents: .none)
        }

        let startIndexOfSignatureFormat = manifest[endIndexOfLabel...]
            .firstIndex(where: { $0 != ":" && !$0.isWhitespace }) ?? manifest.endIndex
        let endIndexOfSignatureFormat = manifest[startIndexOfSignatureFormat...]
            .firstIndex(where: { $0 == ";" }) ?? manifest.endIndex

        // Missing signature format, assume there is no signature.
        guard startIndexOfSignatureFormat < endIndexOfSignatureFormat else {
            return ManifestComponents(contentsBeforeSignatureComponents: manifest[...], signatureComponents: .none)
        }

        let startIndexOfSignatureBase64Encoded = manifest[endIndexOfSignatureFormat...]
            .firstIndex(where: { $0 != ";" }) ?? manifest.endIndex

        // Missing base64-encoded signature, assume there is no signature.
        guard startIndexOfSignatureBase64Encoded < endIndexOfSignatureLine else {
            return ManifestComponents(contentsBeforeSignatureComponents: manifest[...], signatureComponents: .none)
        }

        return ManifestComponents(
            contentsBeforeSignatureComponents: manifest[..<endIndexOfManifestContents],
            signatureComponents: SignatureComponents(
                signatureFormat: manifest[startIndexOfSignatureFormat ..< endIndexOfSignatureFormat],
                signatureBase64Encoded: manifest[startIndexOfSignatureBase64Encoded ... endIndexOfSignatureLine]
            )
        )
    }

    public struct ManifestSignature {
        public let contents: [UInt8]
        public let signatureFormat: String
        public let signature: [UInt8]
    }

    public enum Error: Swift.Error {
        /// Package manifest file is inaccessible (missing, unreadable, etc).
        case inaccessibleManifest(path: AbsolutePath, reason: String)
        /// Malformed manifest signature.
        case malformedManifestSignature
    }
}

extension ManifestSignatureParser {
    /// A representation of a manifest in its constituent parts.
    public struct ManifestComponents {
        /// The contents of the manifest up to the signature line.
        /// A manifest doesn't have to be signed so this can be the entire manifest contents.
        public let contentsBeforeSignatureComponents: Substring
        /// The manifest signature (if any) represented in its constituent parts.
        public let signatureComponents: SignatureComponents?
    }

    /// A representation of manifest signature in its constituent parts.
    ///
    /// A manifest signature consists of the following parts:
    ///
    ///     //  signature:  cms-1.0.0;MIIFujCCBKKgAwIBAgIBATANBgkqhkiG9w0BAQUFAD...
    ///     ⌃~⌃~⌃~~~~~~~~~⌃~⌃~~~~~~~~^^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///     | | |         | |        |└ signature base64-encoded
    ///     │ │ └ label   │ |        └ signature format terminator
    ///     | |           | └ signature format
    ///     │ └ spacing   └ spacing
    ///     └ comment marker
    ///
    public struct SignatureComponents {
        /// The signature format.
        public let signatureFormat: Substring

        /// The base64-encoded signature.
        public let signatureBase64Encoded: Substring
    }
}
