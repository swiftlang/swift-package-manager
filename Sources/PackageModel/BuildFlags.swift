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

    public mutating func merging(_ flags: BuildFlags) -> Self {
        self.cCompilerFlags.insert(contentsOf: flags.cCompilerFlags, at: 0)
        self.cxxCompilerFlags.insert(contentsOf: flags.cxxCompilerFlags, at: 0)
        self.swiftCompilerFlags.insert(contentsOf: flags.swiftCompilerFlags, at: 0)
        self.linkerFlags.insert(contentsOf: flags.linkerFlags, at: 0)
        if self.xcbuildFlags != nil || flags.xcbuildFlags != nil {
            self.xcbuildFlags = (self.xcbuildFlags ?? []) + (flags.xcbuildFlags ?? [])
        }
        return self
    }
}
