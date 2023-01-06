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
        cCompilerFlags: [String]? = .none,
        cxxCompilerFlags: [String]? = .none,
        swiftCompilerFlags: [String]? = .none,
        linkerFlags: [String]? = .none,
        xcbuildFlags: [String]? = .none
    ) {
        self.cCompilerFlags = cCompilerFlags ?? []
        self.cxxCompilerFlags = cxxCompilerFlags ?? []
        self.swiftCompilerFlags = swiftCompilerFlags ?? []
        self.linkerFlags = linkerFlags ?? []
        self.xcbuildFlags = xcbuildFlags ?? []
    }
}
