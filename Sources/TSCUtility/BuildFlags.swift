/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// FIXME: This belongs somewhere else, but we don't have a layer specifically
// for BuildSupport style logic yet.
//
/// Build-tool independent flags.
public struct BuildFlags: Encodable {

    /// Flags to pass to the C compiler.
    public var cCompilerFlags: [String]

    /// Flags to pass to the C++ compiler.
    public var cxxCompilerFlags: [String]

    /// Flags to pass to the linker.
    public var linkerFlags: [String]

    /// Flags to pass to the Swift compiler.
    public var swiftCompilerFlags: [String]

    public init(
        xcc: [String]? = nil,
        xcxx: [String]? = nil,
        xswiftc: [String]? = nil,
        xlinker: [String]? = nil
    ) {
        cCompilerFlags = xcc ?? []
        cxxCompilerFlags = xcxx ?? []
        linkerFlags = xlinker ?? []
        swiftCompilerFlags = xswiftc ?? []
    }
}
