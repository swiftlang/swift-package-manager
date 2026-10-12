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

/// The compilation mode used by the Swift compiler.
@available(_PackageDescription, introduced: 999.0)
public enum CompilationMode: Sendable {
    /// Compile the module's source files incrementally.
    case incremental

    /// Compile all of the module's source files together, enabling whole-module optimization.
    case wholeModule

    var value: String {
        switch self {
        case .incremental: "incremental"
        case .wholeModule: "wholeModule"
        }
    }
}
