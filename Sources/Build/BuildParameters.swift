/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo

import TSCBasic
import TSCUtility

import PackageModel

public struct BuildParameters: Encodable {
    /// Mode for the indexing-while-building feature.
    public enum IndexStoreMode: String, Encodable {
        /// Index store should be enabled.
        case on
        /// Index store should be disabled.
        case off
        /// Index store should be enabled in debug configuration.
        case auto
    }

    /// Represents the debugging strategy.
    ///
    /// Swift binaries requires the swiftmodule files in order for lldb to work.
    /// On Darwin, linker can directly take the swiftmodule file path using the
    /// -add_ast_path flag. On other platforms, we convert the swiftmodule into
    /// an object file using Swift's modulewrap tool.
    enum DebuggingStrategy {
        case swiftAST
        case modulewrap
    }

    /// The path to the data directory.
    public var dataPath: AbsolutePath

    /// The build configuration.
    public var configuration: BuildConfiguration

    /// The toolchain.
    public var toolchain: Toolchain { _toolchain.toolchain }
    private let _toolchain: _Toolchain

    /// Destination triple.
    public var triple: Triple

    /// Extra build flags.
    public var flags: BuildFlags

    /// The tools version to use.
    public var toolsVersion: ToolsVersion

    /// How many jobs should llbuild and the Swift compiler spawn
    public var jobs: UInt32

    /// If should link the Swift stdlib statically.
    public var shouldLinkStaticSwiftStdlib: Bool

    /// Which compiler sanitizers should be enabled
    public var sanitizers: EnabledSanitizers

    /// If should enable llbuild manifest caching.
    public var shouldEnableManifestCaching: Bool

    /// The mode to use for indexing-while-building feature.
    public var indexStoreMode: IndexStoreMode

    /// Whether to enable code coverage.
    public var enableCodeCoverage: Bool

    /// Whether to enable test discovery on platforms without Objective-C runtime.
    public var enableTestDiscovery: Bool

    /// Whether to enable generation of `.swiftinterface` files alongside
    /// `.swiftmodule`s.
    public var enableParseableModuleInterfaces: Bool

    /// Emit Swift module separately from object files. This can enable more parallelism
    /// since downstream targets can begin compiling without waiting for the entire
    /// module to finish building.
    public var emitSwiftModuleSeparately: Bool

    public init(
        dataPath: AbsolutePath,
        configuration: BuildConfiguration,
        toolchain: Toolchain,
        destinationTriple: Triple = Triple.hostTriple,
        flags: BuildFlags,
        toolsVersion: ToolsVersion = ToolsVersion.currentToolsVersion,
        jobs: UInt32 = UInt32(ProcessInfo.processInfo.activeProcessorCount),
        shouldLinkStaticSwiftStdlib: Bool = false,
        shouldEnableManifestCaching: Bool = false,
        sanitizers: EnabledSanitizers = EnabledSanitizers(),
        enableCodeCoverage: Bool = false,
        indexStoreMode: IndexStoreMode = .auto,
        enableParseableModuleInterfaces: Bool = false,
        enableTestDiscovery: Bool = false,
        emitSwiftModuleSeparately: Bool = false
    ) {
        self.dataPath = dataPath
        self.configuration = configuration
        self._toolchain = _Toolchain(toolchain: toolchain)
        self.triple = destinationTriple
        self.flags = flags
        self.toolsVersion = toolsVersion
        self.jobs = jobs
        self.shouldLinkStaticSwiftStdlib = shouldLinkStaticSwiftStdlib
        self.shouldEnableManifestCaching = shouldEnableManifestCaching
        self.sanitizers = sanitizers
        self.enableCodeCoverage = enableCodeCoverage
        self.indexStoreMode = indexStoreMode
        self.enableParseableModuleInterfaces = enableParseableModuleInterfaces
        self.enableTestDiscovery = enableTestDiscovery
        self.emitSwiftModuleSeparately = emitSwiftModuleSeparately
    }

    /// The path to the build directory (inside the data directory).
    public var buildPath: AbsolutePath {
        return dataPath.appending(component: configuration.dirname)
    }

    /// The path to the index store directory.
    public var indexStore: AbsolutePath {
        assert(indexStoreMode != .off, "index store is disabled")
        return buildPath.appending(components: "index", "store")
    }

    /// The path to the code coverage directory.
    public var codeCovPath: AbsolutePath {
        return buildPath.appending(component: "codecov")
    }

    /// The path to the code coverage profdata file.
    public var codeCovDataFile: AbsolutePath {
        return codeCovPath.appending(component: "default.profdata")
    }

    public var llbuildManifest: AbsolutePath {
        return dataPath.appending(components: "..", configuration.dirname + ".yaml")
    }

    public var buildDescriptionPath: AbsolutePath {
        return buildPath.appending(components: "description.json")
    }

    /// Extra flags to pass to Swift compiler.
    public var swiftCompilerFlags: [String] {
        var flags = self.flags.cCompilerFlags.flatMap({ ["-Xcc", $0] })
        flags += self.flags.swiftCompilerFlags
        flags += verbosity.ccArgs
        return flags
    }

    /// Extra flags to pass to linker.
    public var linkerFlags: [String] {
        // Arguments that can be passed directly to the Swift compiler and
        // doesn't require -Xlinker prefix.
        //
        // We do this to avoid sending flags like linker search path at the end
        // of the search list.
        let directSwiftLinkerArgs = ["-L"]

        var flags: [String] = []
        var it = self.flags.linkerFlags.makeIterator()
        while let flag = it.next() {
            if directSwiftLinkerArgs.contains(flag) {
                // `-L <value>` variant.
                flags.append(flag)
                guard let nextFlag = it.next() else {
                    // We expected a flag but don't have one.
                    continue
                }
                flags.append(nextFlag)
            } else if directSwiftLinkerArgs.contains(where: { flag.hasPrefix($0) }) {
                // `-L<value>` variant.
                flags.append(flag)
            } else {
                flags += ["-Xlinker", flag]
            }
        }
        return flags
    }

    /// The debugging strategy according to the current build parameters.
    var debuggingStrategy: DebuggingStrategy? {
        guard configuration == .debug else {
            return nil
        }

        if triple.isDarwin() {
            return .swiftAST
        }
        return .modulewrap
    }
}

/// A shim struct for toolchain so we can encode it without having to write encode(to:) for
/// entire BuildParameters by hand.
private struct _Toolchain: Encodable {
    let toolchain: Toolchain

    enum CodingKeys: String, CodingKey {
        case swiftCompiler
        case clangCompiler
        case extraCCFlags
        case extraSwiftCFlags
        case extraCPPFlags
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolchain.swiftCompiler, forKey: .swiftCompiler)
        try container.encode(toolchain.getClangCompiler(), forKey: .clangCompiler)

        try container.encode(toolchain.extraCCFlags, forKey: .extraCCFlags)
        try container.encode(toolchain.extraCPPFlags, forKey: .extraCPPFlags)
        try container.encode(toolchain.extraSwiftCFlags, forKey: .extraSwiftCFlags)
        try container.encode(toolchain.swiftCompiler, forKey: .swiftCompiler)
    }
}
