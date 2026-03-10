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

public struct BuildFlag: Hashable, Sendable, Encodable {
    public var value: String

    /// Describes the origin of this flag, for example if it was sourced from a Swift SDK, or added as a builtin option by SwiftPM.
    public var source: Source?

    public init(value: String, source: Source?) {
        self.value = value
        self.source = source
    }

    public enum Source: Sendable, Hashable, Codable {
        case defaultSwiftTestingSearchPath
        case defaultWindowsSettings
        case swiftSDK
        case toolset
        case debugging
        case plugin
        case commandLineOptions
    }
}

extension [BuildFlag] {
    public var rawFlags: [String] {
        return self.map(\.value)
    }
}

extension [String] {
    public func constructBuildFlags(source: BuildFlag.Source?) -> [BuildFlag] {
        return self.map {
            BuildFlag(value: $0, source: source)
        }
    }
}

/// Build-tool independent flags.
public struct BuildFlags: Equatable, Encodable {
    /// Flags to pass to the C compiler.
    public var cCompilerFlags: [BuildFlag]

    /// Flags to pass to the C++ compiler.
    public var cxxCompilerFlags: [BuildFlag]

    /// Flags to pass to the Swift compiler.
    public var swiftCompilerFlags: [BuildFlag]

    /// Flags to pass to the linker.
    public var linkerFlags: [BuildFlag]

    /// Flags to pass to xcbuild.
    public var xcbuildFlags: [String]?

    public init(
        cCompilerFlags: [BuildFlag] = [],
        cxxCompilerFlags: [BuildFlag] = [],
        swiftCompilerFlags: [BuildFlag] = [],
        linkerFlags: [BuildFlag] = [],
        xcbuildFlags: [String] = []
    ) {
        self.cCompilerFlags = cCompilerFlags
        self.cxxCompilerFlags = cxxCompilerFlags
        self.swiftCompilerFlags = swiftCompilerFlags
        self.linkerFlags = linkerFlags
        self.xcbuildFlags = xcbuildFlags
    }

    // Kept to allow callers time to migrate to the new initializer.
    @available(*, deprecated, message: "Use the overload which accepts compiler flags as [BuildFlag] instead")
    public init(
        cCompilerFlags: [String],
        cxxCompilerFlags: [String],
        swiftCompilerFlags: [String],
        linkerFlags: [String],
        xcbuildFlags: [String] = []
    ) {
        self.cCompilerFlags = cCompilerFlags.constructBuildFlags(source: nil)
        self.cxxCompilerFlags = cxxCompilerFlags.constructBuildFlags(source: nil)
        self.swiftCompilerFlags = swiftCompilerFlags.constructBuildFlags(source: nil)
        self.linkerFlags = linkerFlags.constructBuildFlags(source: nil)
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
