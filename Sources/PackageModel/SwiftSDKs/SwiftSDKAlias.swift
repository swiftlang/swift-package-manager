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

package struct SwiftSDKAlias {
    init?(_ string: String) {
        guard let kind = Kind(rawValue: string) else { return nil }
        self.kind = kind
    }
    
    enum Kind: String {
        case staticLinux  = "static-linux"
        case wasi         = "wasi"
        case wasiEmbedded = "embedded-wasi"

        var urlFileComponent: String {
            switch self {
            case .staticLinux, .wasi:
                return self.rawValue
            case .wasiEmbedded:
                return Self.wasi.rawValue
            }
        }

        var idComponent: String {
            self.rawValue
        }

        var urlDirComponent: String {
            switch self {
            case .staticLinux:
                "static-sdk"
            case .wasi, .wasiEmbedded:
                "wasi"
            }
        }
    }

    struct Version: CustomStringConvertible {
        let rawValue = "0.0.1"

        var description: String { self.rawValue }
    }

    let kind: Kind
    let defaultVersion = Version()

    var urlFileComponent: String {
        "\(self.kind.urlFileComponent)-\(self.defaultVersion.rawValue)"
    }
}

extension SwiftToolchainVersion {
    package func urlForSwiftSDK(aliasString: String) throws -> String {
        guard let swiftSDKAlias = SwiftSDKAlias(aliasString) else {
            throw Error.unknownSwiftSDKAlias(aliasString)
        }

        return """
        https://download.swift.org/\(
            self.branch
        )/\(
            swiftSDKAlias.kind.urlDirComponent
        )/\(
            self.tag
        )/\(
            self.tag
        )_\(swiftSDKAlias.urlFileComponent).artifactbundle.tar.gz
        """
    }

    package func idForSwiftSDK(aliasString: String) throws -> String {
        guard let swiftSDKAlias = SwiftSDKAlias(aliasString) else {
            throw Error.unknownSwiftSDKAlias(aliasString)
        }

        switch swiftSDKAlias.kind {
        case .staticLinux:
            return "\(self.tag)_\(swiftSDKAlias.kind.idComponent)-\(swiftSDKAlias.defaultVersion)"
        case .wasi, .wasiEmbedded:
            return "\(self.tag.replacing("swift-", with: ""))-wasm32-\(swiftSDKAlias.kind.idComponent)"
        }
    }
}
