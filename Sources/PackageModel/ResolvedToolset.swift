//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

import class TSCBasic.Process

#if os(Windows)
private let hostExecutableSuffix = ".exe"
#else
private let hostExecutableSuffix = ""
#endif

public struct ResolvedToolset {
    typealias SwiftCompilers = (compile: AbsolutePath, manifest: AbsolutePath)

    public struct ToolProperties {
        public let path: AbsolutePath
        public let extraCLIOptions: [String]
    }

    public let targetTriple: Triple

    public let cCompiler: ToolProperties
    public let cxxCompiler: ToolProperties
    public let debugger: ToolProperties
    public let librarian: ToolProperties
    public let swiftCompiler: ToolProperties
    // TODO: Swift compiler for manifests?
    public let swiftPluginServer: ToolProperties?
    public let testRunner: ToolProperties?
    // Note: XCBuild is intentionally not part of the resolved toolset

    public var swiftInterpreter: ToolProperties {
        return ToolProperties(
            path: self.swiftCompiler.path.parentDirectory.appending("swift" + hostExecutableSuffix),
            extraCLIOptions: self.swiftCompiler.extraCLIOptions)
    }

    public enum SearchStrategy {
        case `default`
        case custom(searchPaths: [AbsolutePath], useXcrun: Bool = true)
    }

    /// Search paths from the PATH environment variable.
    let envSearchPaths: [AbsolutePath]

    /// Only use search paths, do not fall back to `xcrun`.
    let useXcrun: Bool

    init(
        sdkRootPath: AbsolutePath?,
        toolset: Toolset,
        triple: Triple?, // FIXME: This sucks because there's still an opportunity to misuse it and compute the triple multiple times.
        environment: EnvironmentVariables = .process(),
        searchStrategy: SearchStrategy = .default
    ) throws {
        switch searchStrategy {
        case .default:
            // Get the search paths from PATH.
            self.envSearchPaths = getEnvSearchPaths(
                pathString: environment.path,
                currentWorkingDirectory: localFileSystem.currentWorkingDirectory
            )
            self.useXcrun = true
        case .custom(let searchPaths, let useXcrun):
            self.envSearchPaths = searchPaths
            self.useXcrun = useXcrun
        }

        let clangCompiler = try Self.getClangCompiler(
            binDirectories: toolset.rootPaths,
            useXcrun: useXcrun,
            environment: environment,
            searchPaths: envSearchPaths
        )

        self.cCompiler = Self.applySwiftSDK(defaultPath: clangCompiler, knownTool: toolset.knownTools[.cCompiler])
        self.cxxCompiler = Self.applySwiftSDK(defaultPath: clangCompiler, knownTool: toolset.knownTools[.cxxCompiler])

        let swiftCompilers = try Self.determineSwiftCompilers(
            binDirectories: toolset.rootPaths,
            useXcrun: useXcrun,
            environment: environment,
            searchPaths: envSearchPaths
        )

        self.swiftCompiler = Self.applySwiftSDK(defaultPath: swiftCompilers.compile, knownTool: toolset.knownTools[.swiftCompiler])
        self.targetTriple = triple! // TOOD: Get host triple if not specified.

        self.debugger = try Self.determineDebugger(
            knownTool: toolset.knownTools[.debugger],
            swiftCompiler: self.swiftCompiler,
            searchPaths: envSearchPaths,
            useXcrun: useXcrun
        )

        self.librarian = try Self.determineLibrarian(
            knownTool: toolset.knownTools[.librarian],
            effectiveTriple: self.targetTriple,
            binDirectories: toolset.rootPaths,
            useXcrun: useXcrun,
            environment: environment,
            searchPaths: envSearchPaths,
            extraSwiftFlags: [] // TODO: Where do we get `self.extraFlags.swiftCompilerFlags` from?
        )

        // TODO: We currently do not handle an overriding linker.
        assert(toolset.knownTools[.linker]?.path == nil, "did not expect linker override")

        if case .custom(_, let useXcrun) = searchStrategy, !useXcrun {
            self.swiftPluginServer = nil

            if let testRunner = toolset.knownTools[.testRunner], let path = testRunner.path {
                self.testRunner = .init(path: path, extraCLIOptions: testRunner.extraCLIOptions)
            } else {
                self.testRunner = nil
            }
        } else {
            if let swiftPluginServerPath = try Self.derivePluginServerPath(triple: self.targetTriple) {
                self.swiftPluginServer = .init(path: swiftPluginServerPath, extraCLIOptions: [])
            } else {
                self.swiftPluginServer = nil
            }

            let extraCLIOptions = toolset.knownTools[.testRunner]?.extraCLIOptions ?? []
            if let testRunnerPath = toolset.knownTools[.testRunner]?.path {
                self.testRunner = .init(path: testRunnerPath, extraCLIOptions: extraCLIOptions)
            } else {
                let defaultXCTestPath = try Self.deriveXCTestPath(
                    sdkRootPath: sdkRootPath,
                    triple: self.targetTriple,
                    environment: environment
                )

                if let defaultXCTestPath = defaultXCTestPath {
                    self.testRunner = .init(path: defaultXCTestPath, extraCLIOptions: extraCLIOptions)
                } else {
                    self.testRunner = nil
                }
            }
        }
    }

    private static func applySwiftSDK(defaultPath: AbsolutePath, knownTool: Toolset.ToolProperties?) -> ToolProperties {
        if let knownTool = knownTool {
            return .init(path: knownTool.path ?? defaultPath, extraCLIOptions: knownTool.extraCLIOptions)
        } else {
            return .init(path: defaultPath, extraCLIOptions: [])
        }
    }

    private static func applySwiftSDK(knownTool: Toolset.ToolProperties?, determineDefaultPath: @escaping (() throws -> AbsolutePath)) throws -> ToolProperties {
        if let knownTool = knownTool, let path = knownTool.path {
            return .init(path: path, extraCLIOptions: knownTool.extraCLIOptions)
        } else {
            return applySwiftSDK(defaultPath: try determineDefaultPath(), knownTool: knownTool)
        }
    }

    static func derivePluginServerPath(triple: Triple) throws -> AbsolutePath? {
        if triple.isDarwin() {
            let xctestFindArgs = ["/usr/bin/xcrun", "--find", "swift-plugin-server"]
            if let path = try? TSCBasic.Process.checkNonZeroExit(arguments: xctestFindArgs, environment: [:])
                .spm_chomp() {
                return try AbsolutePath(validating: path)
            }
        }
        return .none
    }

    static func deriveXCTestPath(
        sdkRootPath: AbsolutePath?,
        triple: Triple,
        environment: EnvironmentVariables
    ) throws -> AbsolutePath? {
        if triple.isDarwin() {
            // XCTest is optional on macOS, for example when Xcode is not installed
            let xctestFindArgs = ["/usr/bin/xcrun", "--sdk", "macosx", "--find", "xctest"]
            if let path = try? TSCBasic.Process.checkNonZeroExit(arguments: xctestFindArgs, environment: environment)
                .spm_chomp()
            {
                return try AbsolutePath(validating: path)
            }
        } else if triple.isWindows() {
            let sdkRoot: AbsolutePath

            if let sdkDir = sdkRootPath {
                sdkRoot = sdkDir
            } else if let SDKROOT = environment["SDKROOT"], let sdkDir = try? AbsolutePath(validating: SDKROOT) {
                sdkRoot = sdkDir
            } else {
                return .none
            }

            // The layout of the SDK is as follows:
            //
            // Library/Developer/Platforms/[PLATFORM].platform/Developer/Library/XCTest-[VERSION]/...
            // Library/Developer/Platforms/[PLATFORM].platform/Developer/SDKs/[PLATFORM].sdk/...
            //
            // SDKROOT points to [PLATFORM].sdk
            let platform = sdkRoot.parentDirectory.parentDirectory.parentDirectory

            if let info = WindowsPlatformInfo(
                reading: platform.appending("Info.plist"),
                observabilityScope: nil,
                filesystem: localFileSystem
            ) {
                let xctest: AbsolutePath =
                    platform.appending("Developer")
                        .appending("Library")
                        .appending("XCTest-\(info.defaults.xctestVersion)")

                // Migration Path
                //
                // In order to support multiple parallel installations of an
                // SDK, we need to ensure that we can have all the architecture
                // variant libraries available.  Prior to this getting enabled
                // (~5.7), we always had a singular installed SDK.  Prefer the
                // new variant which has an architecture subdirectory in `bin`
                // if available.
                switch triple.arch {
                case .x86_64: // amd64 x86_64 x86_64h
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin64")
                    if localFileSystem.exists(path) {
                        return path
                    }

                case .x86: // i386 i486 i586 i686 i786 i886 i986
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin32")
                    if localFileSystem.exists(path) {
                        return path
                    }

                case .arm: // armv7 and many more
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin32a")
                    if localFileSystem.exists(path) {
                        return path
                    }

                case .aarch64: // aarch6 arm64
                    let path: AbsolutePath =
                        xctest.appending("usr")
                            .appending("bin64a")
                    if localFileSystem.exists(path) {
                        return path
                    }

                default:
                    // Fallback to the old-style layout.  We should really
                    // report an error in this case - this architecture is
                    // unavailable.
                    break
                }

                // Assume that we are in the old-style layout.
                return xctest.appending("usr")
                    .appending("bin")
            }
        }
        return .none
    }

    static func determineDebugger(
        knownTool: Toolset.ToolProperties?,
        swiftCompiler: ToolProperties,
        searchPaths: [AbsolutePath],
        useXcrun: Bool
    ) throws -> ToolProperties {
        return try Self.applySwiftSDK(knownTool: knownTool) {
            // Look for LLDB next to the compiler first.
            if let lldbPath = try? Self.getTool("lldb", binDirectories: [swiftCompiler.path.parentDirectory]) {
                return lldbPath
            } else {
                // If that fails, fall back to xcrun, PATH, etc.
                return try Self.findTool("lldb", envSearchPaths: searchPaths, useXcrun: useXcrun)
            }
        }
    }

    static func determineLibrarian(
        knownTool: Toolset.ToolProperties?,
        effectiveTriple: Triple,
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: EnvironmentVariables,
        searchPaths: [AbsolutePath],
        extraSwiftFlags: [String]
    ) throws -> ToolProperties {
        return try Self.applySwiftSDK(knownTool: knownTool) {
            return try Self.determineLibrarian(
                triple: effectiveTriple,
                binDirectories: binDirectories,
                useXcrun: useXcrun,
                environment: environment,
                searchPaths: searchPaths,
                extraSwiftFlags: extraSwiftFlags
            )
        }
    }

    static func determineLibrarian(
        triple: Triple,
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: EnvironmentVariables,
        searchPaths: [AbsolutePath],
        extraSwiftFlags: [String]
    ) throws -> AbsolutePath {
        let variable: String = triple.isApple() ? "LIBTOOL" : "AR"
        let tool: String = {
            if triple.isApple() { return "libtool" }
            if triple.isWindows() {
                if let librarian: AbsolutePath =
                    Self.lookup(
                        variable: "AR",
                        searchPaths: searchPaths,
                        environment: environment
                    )
                {
                    return librarian.basename
                }
                // TODO(5719) handle `-Xmanifest` vs `-Xswiftc`
                // `-use-ld=` is always joined in Swift.
                if let ld = extraSwiftFlags.first(where: { $0.starts(with: "-use-ld=") }) {
                    let linker = String(ld.split(separator: "=").last!)
                    return linker == "lld" ? "lld-link" : linker
                }
                return "link"
            }
            // TODO(compnerd) consider defaulting to `llvm-ar` universally with
            // a fallback to `ar`.
            return triple.isAndroid() ? "llvm-ar" : "ar"
        }()

        if let librarian = Self.lookup(
            variable: variable,
            searchPaths: searchPaths,
            environment: environment
        ) {
            if localFileSystem.isExecutableFile(librarian) {
                return librarian
            }
        }

        if let librarian = try? Self.getTool(tool, binDirectories: binDirectories) {
            return librarian
        }
        return try Self.findTool(tool, envSearchPaths: searchPaths, useXcrun: useXcrun)
    }

    /// Determines the Swift compiler paths for compilation and manifest parsing.
    static func determineSwiftCompilers(
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: EnvironmentVariables,
        searchPaths: [AbsolutePath]
    ) throws -> SwiftCompilers {
        func validateCompiler(at path: AbsolutePath?) throws {
            guard let path else { return }
            guard localFileSystem.isExecutableFile(path) else {
                throw InvalidToolchainDiagnostic(
                    "could not find the `swiftc\(hostExecutableSuffix)` at expected path \(path)"
                )
            }
        }

        let lookup = { Self.lookup(variable: $0, searchPaths: searchPaths, environment: environment) }
        // Get overrides.
        let SWIFT_EXEC_MANIFEST = lookup("SWIFT_EXEC_MANIFEST")
        let SWIFT_EXEC = lookup("SWIFT_EXEC")

        // Validate the overrides.
        try validateCompiler(at: SWIFT_EXEC)
        try validateCompiler(at: SWIFT_EXEC_MANIFEST)

        // We require there is at least one valid swift compiler, either in the
        // bin dir or SWIFT_EXEC.
        let resolvedBinDirCompiler: AbsolutePath
        if let SWIFT_EXEC {
            resolvedBinDirCompiler = SWIFT_EXEC
        } else if let binDirCompiler = try? Self.getTool("swiftc", binDirectories: binDirectories) {
            resolvedBinDirCompiler = binDirCompiler
        } else {
            // Try to lookup swift compiler on the system which is possible when
            // we're built outside of the Swift toolchain.
            resolvedBinDirCompiler = try Self.findTool(
                "swiftc",
                envSearchPaths: searchPaths,
                useXcrun: useXcrun
            )
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (SWIFT_EXEC ?? resolvedBinDirCompiler, SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    /// Returns the path to clang compiler tool.
    static func getClangCompiler(
        binDirectories: [AbsolutePath],
        useXcrun: Bool,
        environment: EnvironmentVariables,
        searchPaths: [AbsolutePath]
    ) throws -> AbsolutePath {
        // Check in the environment variable first.
        if let toolPath = Self.lookup(
            variable: "CC",
            searchPaths: searchPaths,
            environment: environment
        ) {
            return toolPath
        }

        // Then, check the toolchain.
        do {
            if let toolPath = try? Self.getTool("clang", binDirectories: binDirectories) {
                return toolPath
            }
        }

        // Otherwise, lookup it up on the system.
        let toolPath = try Self.findTool("clang", envSearchPaths: searchPaths, useXcrun: useXcrun)
        return toolPath
    }

    private static func findTool(
        _ name: String,
        envSearchPaths: [AbsolutePath],
        useXcrun: Bool
    ) throws -> AbsolutePath {
        if useXcrun {
            #if os(macOS)
            let foundPath = try TSCBasic.Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--find", name])
                .spm_chomp()
            return try AbsolutePath(validating: foundPath)
            #endif
        }

        return try getTool(name, binDirectories: envSearchPaths)
    }

    private static func getTool(_ name: String, binDirectories: [AbsolutePath]) throws -> AbsolutePath {
        let executableName = "\(name)\(hostExecutableSuffix)"
        var toolPath: AbsolutePath?

        for dir in binDirectories {
            let path = dir.appending(component: executableName)
            guard localFileSystem.isExecutableFile(path) else {
                continue
            }
            toolPath = path
        }
        guard let toolPath else {
            throw InvalidToolchainDiagnostic("could not find CLI tool `\(name)` at any of these directories: \(binDirectories)")
        }
        return toolPath
    }

    private static func lookup(
        variable: String,
        searchPaths: [AbsolutePath],
        environment: EnvironmentVariables
    ) -> AbsolutePath? {
        lookupExecutablePath(filename: environment[variable], searchPaths: searchPaths)
    }
}
