/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.URL

extension PackageCollectionsModel {
    /// A representation of a package license
    public struct License {
        /// License type
        public let type: LicenseType

        /// URL of the license file
        public let url: URL
    }

    /// An enum of license types
    public enum LicenseType: CaseIterable, CustomStringConvertible {
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
        case other(String)

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
                return name
            }
        }

        /// All except .other
        public static var allCases: [LicenseType] {
            [.Apache2_0, .BSD2Clause, .BSD3Clause, .GPL2_0, .GPL3_0, .LGPL2_0, .LGPL2_1, .LGPL3_0, .MIT, .MPL2_0, .CDDL1_0, .EPL2_0]
        }
    }
}
