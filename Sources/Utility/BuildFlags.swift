/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Build-tool independent flags.
//
// FIXME: This belongs somewhere else, but we don't have a layer specifically
// for BuildSupport style logic yet.
public struct BuildFlags {
    /// Flags to pass to the C compiler.
    public var cCompilerFlags: [String]

    /// Flags to pass to the linker.
    public var linkerFlags: [String]

    /// Flags to pass to the Swift compiler.
    public var swiftCompilerFlags: [String]

    public init(cCompilerFlags: [String] = [], linkerFlags: [String] = [], swiftCompilerFlags: [String] = []) {
        self.cCompilerFlags = cCompilerFlags
        self.linkerFlags = linkerFlags
        self.swiftCompilerFlags = swiftCompilerFlags
    }
}
