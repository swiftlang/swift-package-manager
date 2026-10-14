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

/// The compiler's optimization level.
@available(_PackageDescription, introduced: 999.0)
public struct OptimizationLevel: Sendable {
    let value: [String]

    private init(_ value: [String]) {
        self.value = value
    }

    /// Compile with no optimization. This is equivalent to passing `-Onone` to the Swift compiler or `-O0` to the C/C++ compiler.
    public static let none: OptimizationLevel = OptimizationLevel(["none"])

    /// Optimize for runtime performance. This is equivalent to passing `-O` to the Swift compiler or `-O2` to the C/C++ compiler.
    public static let speed: OptimizationLevel = OptimizationLevel(["speed"])

    /// Optimize for code size. This is equivalent to passing `-Osize` to the Swift compiler or `-Os` to the C/C++ compiler.
    public static let size: OptimizationLevel = OptimizationLevel(["size"])

    /// Manually specify an optimization level flag to use when compiling, which must begin with `-O`.
    public static func custom(_ flag: String) -> OptimizationLevel {
        OptimizationLevel(["custom", flag])
    }
}
