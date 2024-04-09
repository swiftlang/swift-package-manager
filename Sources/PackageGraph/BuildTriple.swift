//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class PackageModel.Target
import class PackageModel.Product

/// Triple for which code should be compiled for.
/// > Note: We're not using "host" and "target" triple terminology in this enum, as that clashes with build
/// > system "targets" and can lead to confusion in this context.
public enum BuildTriple {
    /// Triple for which build tools are compiled (the host triple).
    case tools

    /// Triple of the destination platform for which end products are compiled (the target triple).
    case destination
}

extension Target {
    var buildTriple: BuildTriple {
        // Make sure that test products are also built for the tools triple.
        // Without this workaround, `assertMacroExpansion` in tests can't be built, as it requires macros
        // and SwiftSyntax to be built for the same triple as the tests.
        // See https://github.com/apple/swift-package-manager/pull/7349 for more context.
        if self.type == .macro || self.type == .plugin || self.type == .test {
            .tools
        } else {
            .destination
        }
    }
}

extension Product {
    var buildTriple: BuildTriple {
        if self.type == .macro || self.type == .plugin || self.type == .test {
            .tools
        } else {
            .destination
        }
    }
}
