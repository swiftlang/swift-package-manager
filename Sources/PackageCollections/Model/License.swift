//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

extension PackageCollectionsModel {
    /// A representation of a package license
    public struct License: Equatable, Codable {
        /// License type
        public let type: LicenseType

        /// URL of the license file
        public let url: URL
    }

    /// An enum of license types
    public enum LicenseType: Equatable, CaseIterable, CustomStringConvertible {
        // This list is taken from https://opensource.org/licenses

        /// Apache License 2.0
        case Apache2_0

        /// BSD 2-Clause license
        case BSD2Clause

        /// BSD 3-Clause license
        case BSD3Clause

        /// GNU General Public License 2.0
        case GPL2_0

        /// GNU General Public License 3.0
        case GPL3_0

        /// GNU Library General Public License 2.0
        case LGPL2_0

        /// GNU Library General Public License 2.1
        case LGPL2_1

        /// GNU Library General Public License 3.0
        case LGPL3_0

        /// MIT license
        case MIT

        /// Mozilla Public License 2.0
        case MPL2_0

        /// Common Development and Distribution License 1.0
        case CDDL1_0

        /// Eclipse Public License version 2.0
        case EPL2_0

        /// Other license type
        case other(String?)

        public var description: String {
            switch self {
            case .Apache2_0:
                return "Apache-2.0"
            case .BSD2Clause:
                return "BSD-2-Clause"
            case .BSD3Clause:
                return "BSD-3-Clause"
            case .GPL2_0:
                return "GPL-2.0"
            case .GPL3_0:
                return "GPL-3.0"
            case .LGPL2_0:
                return "LGPL-2.0"
            case .LGPL2_1:
                return "LGPL-2.1"
            case .LGPL3_0:
                return "LGPL-3.0"
            case .MIT:
                return "MIT"
            case .MPL2_0:
                return "MPL-2.0"
            case .CDDL1_0:
                return "CDDL-1.0"
            case .EPL2_0:
                return "EPL-2.0"
            case .other(let name):
                return name ?? "other"
            }
        }

        /// All except .other
        public static var allCases: [LicenseType] {
            [.Apache2_0, .BSD2Clause, .BSD3Clause, .GPL2_0, .GPL3_0, .LGPL2_0, .LGPL2_1, .LGPL3_0, .MIT, .MPL2_0, .CDDL1_0, .EPL2_0]
        }
    }
}

extension PackageCollectionsModel.LicenseType {
    public init(string: String?) {
        self = string.map { s in Self.allCases.first { $0.description.lowercased() == s.lowercased() } ?? .other(s) } ?? .other(nil)
    }
}

extension PackageCollectionsModel.LicenseType: Codable {
    public enum DiscriminatorKeys: String, Codable {
        case Apache2_0
        case BSD2Clause
        case BSD3Clause
        case GPL2_0
        case GPL3_0
        case LGPL2_0
        case LGPL2_1
        case LGPL3_0
        case MIT
        case MPL2_0
        case CDDL1_0
        case EPL2_0
        case other
    }

    public enum CodingKeys: CodingKey {
        case _case
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DiscriminatorKeys.self, forKey: ._case) {
        case .Apache2_0:
            self = .Apache2_0
        case .BSD2Clause:
            self = .BSD2Clause
        case .BSD3Clause:
            self = .BSD3Clause
        case .GPL2_0:
            self = .GPL2_0
        case .GPL3_0:
            self = .GPL3_0
        case .LGPL2_0:
            self = .LGPL2_0
        case .LGPL2_1:
            self = .LGPL2_1
        case .LGPL3_0:
            self = .LGPL3_0
        case .MIT:
            self = .MIT
        case .MPL2_0:
            self = .MPL2_0
        case .CDDL1_0:
            self = .CDDL1_0
        case .EPL2_0:
            self = .EPL2_0
        case .other:
            let name = try container.decode(String.self, forKey: .name)
            self = .other(name)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .Apache2_0:
            try container.encode(DiscriminatorKeys.Apache2_0, forKey: ._case)
        case .BSD2Clause:
            try container.encode(DiscriminatorKeys.BSD2Clause, forKey: ._case)
        case .BSD3Clause:
            try container.encode(DiscriminatorKeys.BSD3Clause, forKey: ._case)
        case .GPL2_0:
            try container.encode(DiscriminatorKeys.GPL2_0, forKey: ._case)
        case .GPL3_0:
            try container.encode(DiscriminatorKeys.GPL3_0, forKey: ._case)
        case .LGPL2_0:
            try container.encode(DiscriminatorKeys.LGPL2_0, forKey: ._case)
        case .LGPL2_1:
            try container.encode(DiscriminatorKeys.LGPL2_1, forKey: ._case)
        case .LGPL3_0:
            try container.encode(DiscriminatorKeys.LGPL3_0, forKey: ._case)
        case .MIT:
            try container.encode(DiscriminatorKeys.MIT, forKey: ._case)
        case .MPL2_0:
            try container.encode(DiscriminatorKeys.MPL2_0, forKey: ._case)
        case .CDDL1_0:
            try container.encode(DiscriminatorKeys.CDDL1_0, forKey: ._case)
        case .EPL2_0:
            try container.encode(DiscriminatorKeys.EPL2_0, forKey: ._case)
        case .other(let name):
            try container.encode(DiscriminatorKeys.other, forKey: ._case)
            try container.encode(name, forKey: .name)
        }
    }
}
