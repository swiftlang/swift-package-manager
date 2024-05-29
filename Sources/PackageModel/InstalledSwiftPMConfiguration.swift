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

public struct InstalledSwiftPMConfiguration {
    public struct Version: Codable, CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int
        let prereleaseIdentifier: String?

        public init(major: Int, minor: Int, patch: Int, prereleaseIdentifier: String? = nil) {
            self.major = major
            self.minor = minor
            self.patch = patch
            self.prereleaseIdentifier = prereleaseIdentifier
        }

        public var description: String {
            return "\(major).\(minor).\(patch)\(prereleaseIdentifier.map { "-\($0)" } ?? "")"
        }
    }

    let version: Int
    public let swiftSyntaxVersionForMacroTemplate: Version
    public let swiftTestingVersionForTestTemplate: Version

    public static var `default`: InstalledSwiftPMConfiguration {
        return .init(
            version: 0,
            swiftSyntaxVersionForMacroTemplate: .init(
                major: 600,
                minor: 0,
                patch: 0,
                prereleaseIdentifier: "latest"
            ),
            swiftTestingVersionForTestTemplate: defaultSwiftTestingVersionForTestTemplate
        )
    }

    private static var defaultSwiftTestingVersionForTestTemplate: Version {
        .init(
            major: 0,
            minor: 8,
            patch: 0,
            prereleaseIdentifier: nil
        )
    }
}

extension InstalledSwiftPMConfiguration: Codable {
    enum CodingKeys: CodingKey {
        case version
        case swiftSyntaxVersionForMacroTemplate
        case swiftTestingVersionForTestTemplate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.version = try container.decode(
            Int.self,
            forKey: CodingKeys.version
        )
        self.swiftSyntaxVersionForMacroTemplate = try container.decode(
            Version.self,
            forKey: CodingKeys.swiftSyntaxVersionForMacroTemplate
        )
        self.swiftTestingVersionForTestTemplate = try container.decodeIfPresent(
            Version.self,
            forKey: CodingKeys.swiftTestingVersionForTestTemplate
        ) ?? InstalledSwiftPMConfiguration.defaultSwiftTestingVersionForTestTemplate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.version, forKey: CodingKeys.version)
        try container.encode(
            self.swiftSyntaxVersionForMacroTemplate,
            forKey: CodingKeys.swiftSyntaxVersionForMacroTemplate
        )
        try container.encode(
            self.swiftTestingVersionForTestTemplate,
            forKey: CodingKeys.swiftTestingVersionForTestTemplate
        )
  }
}
