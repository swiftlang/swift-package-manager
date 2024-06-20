//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath

public final class BinaryTarget: Target {
    /// The kind of binary artifact.
    public let kind: Kind

    /// The original source of the binary artifact.
    public let origin: Origin

    /// The binary artifact path.
    public var artifactPath: AbsolutePath {
        return self.sources.root
    }

    public init(
        name: String,
        kind: Kind,
        path: AbsolutePath,
        origin: Origin
    ) {
        self.origin = origin
        self.kind = kind
        let sources = Sources(paths: [], root: path)
        super.init(
            name: name,
            type: .binary,
            path: .root,
            sources: sources,
            dependencies: [],
            packageAccess: false,
            buildSettings: .init(),
            buildSettingsDescription: [],
            pluginUsages: [],
            usesUnsafeFlags: false
        )
    }

    public enum Kind: String, RawRepresentable, CaseIterable {
        case xcframework
        case artifactsArchive
        case unknown // for non-downloaded artifacts

        public var fileExtension: String {
            switch self {
            case .xcframework:
                return "xcframework"
            case .artifactsArchive:
                return "artifactbundle"
            case .unknown:
                return "unknown"
            }
        }
    }

    public var containsExecutable: Bool {
        // FIXME: needs to be revisited once libraries are supported in artifact bundles
        return self.kind == .artifactsArchive
    }

    public enum Origin: Equatable {

        /// Represents an artifact that was downloaded from a remote URL.
        case remote(url: String)

        /// Represents an artifact that was available locally.
        case local
    }
}
