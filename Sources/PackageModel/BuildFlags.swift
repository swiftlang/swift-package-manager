//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Build-tool independent flags.
public struct BuildFlags: Equatable, Encodable {
    /// Flags to pass to the C compiler.
    public var cCompilerFlags: [String]

    /// Flags to pass to the C++ compiler.
    public var cxxCompilerFlags: [String]

    /// Flags to pass to the Swift compiler.
    public var swiftCompilerFlags: [String]

    /// Flags to pass to the linker.
    public var linkerFlags: [String]

    /// Flags to pass to xcbuild.
    public var xcbuildFlags: [String]?

    public init(
        cCompilerFlags: [String] = [],
        cxxCompilerFlags: [String] = [],
        swiftCompilerFlags: [String] = [],
        linkerFlags: [String] = [],
        xcbuildFlags: [String] = []
    ) {
        self.cCompilerFlags = cCompilerFlags
        self.cxxCompilerFlags = cxxCompilerFlags
        self.swiftCompilerFlags = swiftCompilerFlags
        self.linkerFlags = linkerFlags
        self.xcbuildFlags = xcbuildFlags
    }
    
    /// Appends corresponding properties of a different `BuildFlags` value into `self`.
    /// - Parameter buildFlags: a `BuildFlags` value to merge flags from.
    public mutating func append(_ buildFlags: BuildFlags) {
        cCompilerFlags += buildFlags.cCompilerFlags
        cxxCompilerFlags += buildFlags.cxxCompilerFlags
        swiftCompilerFlags += buildFlags.swiftCompilerFlags
        linkerFlags += buildFlags.linkerFlags

        if var xcbuildFlags, let newXcbuildFlags = buildFlags.xcbuildFlags {
            xcbuildFlags += newXcbuildFlags
            self.xcbuildFlags = xcbuildFlags
        } else if let xcbuildFlags = buildFlags.xcbuildFlags {
            self.xcbuildFlags = xcbuildFlags
        }
    }
}
