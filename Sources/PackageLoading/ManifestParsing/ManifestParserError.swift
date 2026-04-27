//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if !DISABLE_PARSING_MANIFEST_LOADER
import Basics
import Foundation
import PackageModel
import SwiftDiagnostics

/// An error that can be produced when parsing a manifest directly.
public enum ManifestParserError: Error {
    /// The manifest parser encountered known limitations and cannot produce
    /// a complete manifest.
    case limitations([ManifestParseLimitation])

    /// The parser encountered syntactic errors when parsing the manifest.
    case syntaxErrors([SwiftDiagnostics.Diagnostic])

    /// The manifest file could not be loaded.
    case inaccessibleManifest(path: AbsolutePath, reason: String)

    /// The manifest file is missing a package name.
    case missingPackageName

    /// Unhandled Swift language mode.
    case unknownLanguageMode(SwiftLanguageVersion)
}

extension ManifestParserError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .limitations(let limitations):
            return "Manifest parser encountered limitations\n" + limitations.map(\.description).joined(separator: "\n")
        case .syntaxErrors:
            return "Syntax errors in manifest"
        case .inaccessibleManifest(path: let path, reason: let reason):
            return "Could not read package manifest at \(path): \(reason)"
        case .missingPackageName:
            return "Could not find the package name"
        case .unknownLanguageMode(let version):
            return "Could not handle language mode \(version)"
        }
    }
}

extension ManifestParserError: LocalizedError {
    public var errorDescription: String? {
        description
    }
}
#endif
