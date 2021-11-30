/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import struct Foundation.URL
import TSCUtility

public struct Fingerprint: Equatable {
    public let origin: Origin
    public let value: String
}

public extension Fingerprint {
    enum Kind: String, Hashable {
        case sourceControl
        case registry
    }

    enum Origin: Equatable, CustomStringConvertible {
        case sourceControl(Foundation.URL)
        case registry(Foundation.URL)

        var kind: Fingerprint.Kind {
            switch self {
            case .sourceControl:
                return .sourceControl
            case .registry:
                return .registry
            }
        }

        var url: Foundation.URL? {
            switch self {
            case .sourceControl(let url):
                return url
            case .registry(let url):
                return url
            }
        }

        public var description: String {
            switch self {
            case .sourceControl(let url):
                return "sourceControl(\(url))"
            case .registry(let url):
                return "registry(\(url))"
            }
        }
    }
}

public typealias PackageFingerprints = [Version: [Fingerprint.Kind: Fingerprint]]
