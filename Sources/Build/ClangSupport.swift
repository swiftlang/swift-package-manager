//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import PackageModel

public enum ClangSupport {
    private struct Feature: Decodable {
        let name: String
        let value: [String]?
    }

    private struct Features: Decodable {
        let features: [Feature]
    }

    private static var cachedFeatures = ThreadSafeBox<Features>()

    public static func supportsFeature(name: String, toolchain: PackageModel.Toolchain) throws -> Bool {
        let features = try cachedFeatures.memoize {
            let clangPath = try toolchain.getClangCompiler()
            let featuresPath = clangPath.parentDirectory.parentDirectory.appending(components: ["share", "clang", "features.json"])
            return try JSONDecoder.makeWithDefaults().decode(
                path: featuresPath,
                fileSystem: localFileSystem,
                as: Features.self
            )
        }
        return features.features.first(where: { $0.name == name }) != nil
    }
}
