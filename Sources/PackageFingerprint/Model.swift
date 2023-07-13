//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Foundation.URL

import Basics
import PackageModel
import struct TSCUtility.Version

public struct Fingerprint: Equatable {
    public let origin: Origin
    public let value: String
    public let contentType: ContentType

    public init(origin: Origin, value: String, contentType: ContentType) {
        self.origin = origin
        self.value = value
        self.contentType = contentType
    }
}

extension Fingerprint {
    public enum Kind: String, Hashable {
        case sourceControl
        case registry
    }

    public enum Origin: Equatable, CustomStringConvertible {
        case sourceControl(SourceControlURL)
        case registry(URL)

        public var kind: Fingerprint.Kind {
            switch self {
            case .sourceControl:
                return .sourceControl
            case .registry:
                return .registry
            }
        }

        public var url: SourceControlURL? {
            switch self {
            case .sourceControl(let url):
                return url
            case .registry(let url):
                return SourceControlURL(url.absoluteString)
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

    /// Each package version has a dictionary of fingerprints identified by content type.
    /// Fingerprints of content type `sourceCode` can come from registry (i.e., source archive checksum)
    /// or git repo (commit hash). However, the current implementation only stores fingerprints for manifests
    /// downloaded from registry. It doesn't not save fingerprints for manifests in git repo.
    public enum ContentType: Hashable, CustomStringConvertible {
        case sourceCode
        case manifest(ToolsVersion?)

        public var description: String {
            switch self {
            case .sourceCode:
                return "sourceCode"
            case .manifest(.none):
                return Manifest.filename
            case .manifest(.some(let toolsVersion)):
                return "Package@swift-\(toolsVersion).swift"
            }
        }
    }
}

public typealias PackageFingerprints = [Version: [Fingerprint.Kind: [Fingerprint.ContentType: Fingerprint]]]

public enum FingerprintCheckingMode: String {
    case strict
    case warn
}
