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

import struct Basics.Triple
import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration
import class PackageModel.UserToolchain

extension BuildSystemProvider.Kind {

    @available(*, deprecated, message: "use binPath(for:scrathPath:triple) instead")
    public func binPathSuffixes(for config: BuildConfiguration) -> [String] {
        let suffix: String

        #if os(Linux)
        suffix = "-linux"
        #elseif os(Windows)
        suffix = "-windows"
        #else
        suffix = ""
        #endif
        switch self {
            case .native:
                return ["\(config)".lowercased()]
            case .swiftbuild:
                return ["Products" , "\(config)".capitalized + suffix]
            case .xcode:
                return ["apple", "Products" , "\(config)".capitalized + suffix]
        }
    }

    public func binPath(
        for config: BuildConfiguration,
        scratchPath: [String] = [".build"],
        triple: String? = nil,
    ) -> [String] {
        let suffix: String
        let tripleString: String
        let targetTriple: Triple
        if let triple {
            targetTriple = try Triple(triple)
            tripleString = triple
        } else {
            targetTriple = try UserToolchain.default.targetTriple
            tripleString = targetTriple.platformBuildPathComponent
        }

        if targetTriple.isLinux() {
            suffix = "-linux"
        } else if targetTriple.isWindows() {
            suffix = "-windows"
        } else {
            suffix = ""
        }

        switch self {
        case .native:
            return scratchPath + [tripleString, "\(config)".lowercased()]
        case .swiftbuild, .xcode:
            return scratchPath + ["out", "Products", "\(config)".capitalized + suffix]
        }
    }

}
