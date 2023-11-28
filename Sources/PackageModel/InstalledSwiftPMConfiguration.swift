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

public struct InstalledSwiftPMConfiguration: Codable {
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

    public static var `default`: InstalledSwiftPMConfiguration {
        return .init(version: 0, swiftSyntaxVersionForMacroTemplate: .init(major: 509, minor: 0, patch: 0))
    }
}
