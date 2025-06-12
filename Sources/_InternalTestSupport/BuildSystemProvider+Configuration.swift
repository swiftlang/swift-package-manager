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

import struct SPMBuildCore.BuildSystemProvider
import enum PackageModel.BuildConfiguration

extension BuildSystemProvider.Kind {

    public func binPathSuffixes(for config: BuildConfiguration) -> [String] {
        switch self {
            case .native:
                return ["\(config)".lowercased()]
            case .swiftbuild:
                return ["Products" , "\(config)".capitalized]
            case .xcode:
                return ["apple", "Products" , "\(config)".capitalized]
        }
    }
}
