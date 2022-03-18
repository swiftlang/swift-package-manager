//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

import struct TSCUtility.Version

public struct Fingerprint: Equatable {
    public let origin: Origin
    public let value: String

    public init(origin: Origin, value: String) {
        self.origin = origin
        self.value = value
    }
}

public extension Fingerprint {
    enum Kind: String, Hashable {
        case sourceControl
        case registry
    }

    enum Origin: Equatable, CustomStringConvertible {
        case sourceControl(URL)
        case registry(URL)

        public var kind: Fingerprint.Kind {
            switch self {
            case .sourceControl:
                return .sourceControl
            case .registry:
                return .registry
            }
        }

        public var url: URL? {
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

public enum FingerprintCheckingMode: String {
    case strict
    case warn
}
