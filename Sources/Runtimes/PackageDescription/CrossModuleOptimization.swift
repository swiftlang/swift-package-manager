//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The cross-module optimization mode used by the Swift compiler.
@available(_PackageDescription, introduced: 999.0)
public enum CrossModuleOptimization: Sendable {
    /// Use the compiler's default cross-module optimization behavior.
    case `default`

    /// Disable cross-module optimization.
    case disabled

    /// Use the compiler's aggressive cross-module optimization behavior.
    case aggressive

    var value: String {
        switch self {
        case .default: "default"
        case .disabled: "disabled"
        case .aggressive: "aggressive"
        }
    }
}
