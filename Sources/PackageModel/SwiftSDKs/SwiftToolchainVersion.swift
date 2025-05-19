//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import class Foundation.JSONDecoder
import struct Foundation.URL

package struct SwiftToolchainVersion: Equatable, Decodable {
    package enum Error: Swift.Error, Equatable {
        case versionMetadataNotFound(AbsolutePath)
        case unknownSwiftSDKAlias(String)
    }

    package init(
        tag: String,
        branch: String,
        architecture: SwiftToolchainVersion.Architecture,
        platform: SwiftToolchainVersion.Platform
    ) {
        self.tag = tag
        self.branch = branch
        self.architecture = architecture
        self.platform = platform
    }

    /// Since triples don't encode the platform, we use platform identifiers
    /// that match swift.org toolchain distribution names.
    package enum Platform: String, Decodable {
        case macOS
        case ubuntu2004
        case ubuntu2204
        case ubuntu2404
        case debian12
        case amazonLinux2
        case fedora39
        case fedora41
        case ubi9

        var urlDirComponent: String {
            switch self {
            case .macOS:
                "xcode"
            case .ubuntu2004:
                "ubuntu2004"
            case .ubuntu2204:
                "ubuntu2204"
            case .ubuntu2404:
                "ubuntu2404"
            case .debian12:
                "debian12"
            case .amazonLinux2:
                "amazonlinux2"
            case .fedora39:
                "fedora39"
            case .fedora41:
                "fedora41"
            case .ubi9:
                "ubi9"
            }
        }

        var urlFileComponent: String {
            switch self {
            case .macOS:
                "osx"
            case .ubuntu2004:
                "ubuntu20.04"
            case .ubuntu2204:
                "ubuntu22.04"
            case .ubuntu2404:
                "ubuntu24.04"
            case .debian12:
                "debian12"
            case .amazonLinux2:
                "amazonlinux2"
            case .fedora39:
                "fedora39"
            case .fedora41:
                "fedora41"
            case .ubi9:
                "ubi9"
            }
        }
    }

    package enum Architecture: String, Decodable {
        case aarch64
        case x86_64

        var urlFileComponent: String {
            switch self {
            case .aarch64:
                "-aarch64"
            case .x86_64:
                ""
            }
        }
    }

    /// A Git tag from which this toolchain was built.
    package let tag: String

    /// Branch from which this toolchain was built.
    package let branch: String

    /// CPU architecture on which this toolchain runs.
    package let architecture: Architecture

    /// Platform identifier on which this toolchain runs.
    package let platform: Platform

    package func generateURL(aliasString: String) throws -> String {
        guard let swiftSDKAlias = SwiftSDKAlias(aliasString) else {
            throw Error.unknownSwiftSDKAlias(aliasString)
        }

        return """
            https://download.swift.org/\(
                self.branch
            )/\(
                self.tag
            )/\(
                self.tag
            )_\(swiftSDKAlias.urlFileComponent).artifactbundle.tar.gz
            """
    }

    package init(toolchain: some Toolchain, fileSystem: any FileSystem) throws {
        let versionMetadataPath = try toolchain.swiftCompilerPath.parentDirectory.parentDirectory.appending(
            RelativePath(validating: "lib/swift/version.json")
        )
        guard fileSystem.exists(versionMetadataPath) else {
            throw Error.versionMetadataNotFound(versionMetadataPath)
        }

        self = try JSONDecoder().decode(
            path: versionMetadataPath,
            fileSystem: fileSystem,
            as: Self.self
        )
    }
}

package struct SwiftSDKAlias {
    init?(_ string: String) {
        guard let kind = Kind(rawValue: string) else { return nil }
        self.kind = kind
    }
    
    enum Kind: String {
        case staticLinux  = "static-linux"
        case wasi         = "wasi"
        case wasiEmbedded = "wasi-embedded"

        var urlFileComponent: String {
            switch self {
            case .staticLinux, .wasi:
                return self.rawValue
            case .wasiEmbedded:
                return Self.wasi.rawValue
            }
        }
    }

    struct Version {
        let rawValue = "0.0.1"
    }

    let kind: Kind
    let defaultVersion = Version()

    var urlFileComponent: String {
        "\(self.kind.urlFileComponent)-\(self.defaultVersion.rawValue)"
    }
}
