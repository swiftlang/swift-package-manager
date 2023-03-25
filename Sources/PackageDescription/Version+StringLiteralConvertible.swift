//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Version: ExpressibleByStringLiteral {
    /// Initializes a version struct with the provided string literal.
    ///
    /// - Parameter version: A string literal to use for creating a new version struct.
    public init(stringLiteral value: String) {
        if let version = Version(value) {
            self = version
        } else {
            // If version can't be initialized using the string literal, report
            // the error and initialize with a dummy value. This is done to
            // report error to the invoking tool (like swift build) gracefully
            // rather than just crashing.
            errors.append("Invalid semantic version string '\(value)'")
            self.init(0, 0, 0)
        }
    }

    /// Initializes a version struct with the provided extended grapheme cluster.
    ///
    /// - Parameter version: An extended grapheme cluster to use for creating a new
    ///   version struct.
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    /// Initializes a version struct with the provided Unicode string.
    ///
    /// - Parameter version: A Unicode string to use for creating a new version struct.
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension Version: LosslessStringConvertible {
    /// Initializes a version struct with the provided version string.
    /// - Parameter version: A version string to use for creating a new version struct.
    public init?(_ versionString: String) {
        // SemVer 2.0.0 allows only ASCII alphanumerical characters and "-" in the version string, except for "." and "+" as delimiters. ("-" is used as a delimiter between the version core and pre-release identifiers, but it's allowed within pre-release and metadata identifiers as well.)
        // Alphanumerics check will come later, after each identifier is split out (i.e. after the delimiters are removed).
        guard versionString.allSatisfy(\.isASCII) else { return nil }

        let metadataDelimiterIndex = versionString.firstIndex(of: "+")
        // SemVer 2.0.0 requires that pre-release identifiers come before build metadata identifiers
        let prereleaseDelimiterIndex = versionString[..<(metadataDelimiterIndex ?? versionString.endIndex)].firstIndex(of: "-")

        let versionCore = versionString[..<(prereleaseDelimiterIndex ?? metadataDelimiterIndex ?? versionString.endIndex)]
        let versionCoreIdentifiers = versionCore.split(separator: ".", omittingEmptySubsequences: false)

        guard
            versionCoreIdentifiers.count == 3,
            // Major, minor, and patch versions must be ASCII numbers, according to the semantic versioning standard.
            // Converting each identifier from a substring to an integer doubles as checking if the identifiers have non-numeric characters.
                let major = Int(versionCoreIdentifiers[0]),
            let minor = Int(versionCoreIdentifiers[1]),
            let patch = Int(versionCoreIdentifiers[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch

        if let prereleaseDelimiterIndex {
            let prereleaseStartIndex = versionString.index(after: prereleaseDelimiterIndex)
            let prereleaseIdentifiers = versionString[prereleaseStartIndex..<(metadataDelimiterIndex ?? versionString.endIndex)].split(separator: ".", omittingEmptySubsequences: false)
            guard prereleaseIdentifiers.allSatisfy({ $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })}) else { return nil }
            self.prereleaseIdentifiers = prereleaseIdentifiers.map { String($0) }
        } else {
            self.prereleaseIdentifiers = []
        }

        if let metadataDelimiterIndex {
            let metadataStartIndex = versionString.index(after: metadataDelimiterIndex)
            let buildMetadataIdentifiers = versionString[metadataStartIndex...].split(separator: ".", omittingEmptySubsequences: false)
            guard buildMetadataIdentifiers.allSatisfy({ $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })}) else { return nil }
            self.buildMetadataIdentifiers = buildMetadataIdentifiers.map { String($0) }
        } else {
            self.buildMetadataIdentifiers = []
        }
    }
}
