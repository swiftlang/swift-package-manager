/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Version: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        if let version = Version(value.characters) {
            self.init(version)
        } else {
            // If version can't be initialized using the string literal, report the error and initialize with a dummy
            // value. This is done to fail the invoking tool (like swift build) gracefully rather than just crashing.
            errors.add("Invalid version string: \(value)")
            self.init(0, 0, 0)
        }
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension Version {

    public init(_ version: Version) {
        major = version.major
        minor = version.minor
        patch = version.patch
        prereleaseIdentifiers = version.prereleaseIdentifiers
        buildMetadataIdentifier = version.buildMetadataIdentifier
    }

    public init?(_ versionString: String) {
        self.init(versionString.characters)
    }

    public init?(_ characters: String.CharacterView) {
        let prereleaseStartIndex = characters.index(of: "-")
        let metadataStartIndex = characters.index(of: "+")

        let requiredEndIndex = prereleaseStartIndex ?? metadataStartIndex ?? characters.endIndex
        let requiredCharacters = characters.prefix(upTo: requiredEndIndex)
        let requiredStringComponents = requiredCharacters
            .split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
            .map(String.init)
        let requiredComponents = requiredStringComponents.flatMap({ Int($0) }).filter({ $0 >= 0 })

        guard requiredComponents.count == 3 else {
            return nil
        }

        self.major = requiredComponents[0]
        self.minor = requiredComponents[1]
        self.patch = requiredComponents[2]

        if let prereleaseStartIndex = prereleaseStartIndex {
            let prereleaseEndIndex = metadataStartIndex ?? characters.endIndex
            let prereleaseCharacters = characters[characters.index(after: prereleaseStartIndex)..<prereleaseEndIndex]
            prereleaseIdentifiers = prereleaseCharacters.split(separator: ".").map(String.init)
        } else {
            prereleaseIdentifiers = []
        }

        var buildMetadataIdentifier: String? = nil
        if let metadataStartIndex = metadataStartIndex {
            let buildMetadataCharacters = characters.suffix(from: characters.index(after: metadataStartIndex))
            if !buildMetadataCharacters.isEmpty {
                buildMetadataIdentifier = String(buildMetadataCharacters)
            }
        }
        self.buildMetadataIdentifier = buildMetadataIdentifier
    }
}
