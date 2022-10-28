/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

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

    public init(
        cCompilerFlags: [String]? = nil,
        cxxCompilerFlags: [String]? = nil,
        swiftCompilerFlags: [String]? = nil,
        linkerFlags: [String]? = nil
    ) {
        self.cCompilerFlags = cCompilerFlags ?? []
        self.cxxCompilerFlags = cxxCompilerFlags ?? []
        self.swiftCompilerFlags = swiftCompilerFlags ?? []
        self.linkerFlags = linkerFlags ?? []
    }
}
