/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic
import TSCUtility
import PackageLoading
import SPMBuildCore
import Build
import Foundation

#if os(Windows)
private let hostExecutableSuffix = ".exe"
#else
private let hostExecutableSuffix = ""
#endif

// FIXME: This is messy and needs a redesign.
public final class UserToolchain: Toolchain {

    /// The manifest resource provider.
    public let manifestResources: ManifestResourceProvider

    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath

    public var extraCCFlags: [String]

    public let extraSwiftCFlags: [String]

    public var extraCPPFlags: [String]

    /// Path of the `swift` interpreter.
    public var swiftInterpreter: AbsolutePath {
        return swiftCompiler.parentDirectory.appending(component: "swift" + hostExecutableSuffix)
    }

    /// Path to the xctest utility.
    ///
    /// This is only present on macOS.
    public let xctest: AbsolutePath?

    /// The compilation destination object.
    public let destination: Destination

    /// The target triple that should be used for compilation.
    public let triple: Triple

    /// The list of archs to build for.
    public let archs: [String]

    /// Search paths from the PATH environment variable.
    let envSearchPaths: [AbsolutePath]

    /// Returns the runtime library for the given sanitizer.
    public func runtimeLibrary(for sanitizer: Sanitizer) throws -> AbsolutePath {
        // FIXME: This is only for SwiftPM development time support. It is OK
        // for now but we shouldn't need to resolve the symlink.  We need to lay
        // down symlinks to runtimes in our fake toolchain as part of the
        // bootstrap script.
        let swiftCompiler = resolveSymlinks(self.swiftCompiler)

        let runtime = swiftCompiler.appending(
            RelativePath("../../lib/swift/clang/lib/darwin/libclang_rt.\(sanitizer.shortName)_osx_dynamic.dylib"))

        // Ensure that the runtime is present.
        guard localFileSystem.exists(runtime) else {
            throw InvalidToolchainDiagnostic("Missing runtime for \(sanitizer) sanitizer")
        }

        return runtime
    }

    private static func getTool(_ name: String, binDir: AbsolutePath) throws -> AbsolutePath {
        let executableName = "\(name)\(hostExecutableSuffix)"
        let toolPath = binDir.appending(component: executableName)
        guard localFileSystem.isExecutableFile(toolPath) else {
            throw InvalidToolchainDiagnostic("could not find \(name) at expected path \(toolPath)")
        }
        return toolPath
    }

    private static func findTool(_ name: String, envSearchPaths: [AbsolutePath]) throws -> AbsolutePath {
#if os(macOS)
        let foundPath = try Process.checkNonZeroExit(arguments: ["/usr/bin/xcrun", "--find", name]).spm_chomp()
        return try AbsolutePath(validating: foundPath)
#else
        for folder in envSearchPaths {
            if let toolPath = try? getTool(name, binDir: folder) {
                return toolPath
            }
        }
        throw InvalidToolchainDiagnostic("could not find \(name)")
#endif
    }

    /// Determines the Swift compiler paths for compilation and manifest parsing.
    private static func determineSwiftCompilers(binDir: AbsolutePath, lookup: (String) -> AbsolutePath?, envSearchPaths: [AbsolutePath]) throws -> (compile: AbsolutePath, manifest: AbsolutePath) {
        func validateCompiler(at path: AbsolutePath?) throws {
            guard let path = path else { return }
            guard localFileSystem.isExecutableFile(path) else {
                throw InvalidToolchainDiagnostic("could not find the `swiftc\(hostExecutableSuffix)` at expected path \(path)")
            }
        }

        // Get overrides.
        let SWIFT_EXEC_MANIFEST = lookup("SWIFT_EXEC_MANIFEST")
        let SWIFT_EXEC = lookup("SWIFT_EXEC")

        // Validate the overrides.
        try validateCompiler(at: SWIFT_EXEC)
        try validateCompiler(at: SWIFT_EXEC_MANIFEST)

        // We require there is at least one valid swift compiler, either in the
        // bin dir or SWIFT_EXEC.
        let resolvedBinDirCompiler: AbsolutePath
        if let SWIFT_EXEC = SWIFT_EXEC {
            resolvedBinDirCompiler = SWIFT_EXEC
        } else if let binDirCompiler = try? UserToolchain.getTool("swiftc", binDir: binDir) {
            resolvedBinDirCompiler = binDirCompiler
        } else {
            // Try to lookup swift compiler on the system which is possible when
            // we're built outside of the Swift toolchain.
            resolvedBinDirCompiler = try UserToolchain.findTool("swiftc", envSearchPaths: envSearchPaths)
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (SWIFT_EXEC ?? resolvedBinDirCompiler, SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    private static func lookup(variable: String, searchPaths: [AbsolutePath]) -> AbsolutePath? {
        return lookupExecutablePath(filename: ProcessEnv.vars[variable], searchPaths: searchPaths)
    }

    /// Environment to use when looking up tools.
    private let processEnvironment: [String: String]

    /// Returns the path to clang compiler tool.
    public func getClangCompiler() throws -> AbsolutePath {
        // Check if we already computed.
        if let clang = _clangCompiler {
            return clang
        }

        // Check in the environment variable first.
        if let toolPath = UserToolchain.lookup(variable: "CC", searchPaths: envSearchPaths) {
            _clangCompiler = toolPath
            return toolPath
        }

        // Then, check the toolchain.
        do {
            if let toolPath = try? UserToolchain.getTool("clang", binDir: destination.binDir) {
                _clangCompiler = toolPath
                return toolPath
            }
        }

        // Otherwise, lookup it up on the system.
        let toolPath = try UserToolchain.findTool("clang", envSearchPaths: envSearchPaths)
        _clangCompiler = toolPath
        return toolPath
    }
    private var _clangCompiler: AbsolutePath?

    public func _isClangCompilerVendorApple() throws -> Bool? {
        // Assume the vendor is Apple on macOS.
        // FIXME: This might not be the best way to determine this.
      #if os(macOS)
        return true
      #else
        return false
      #endif
    }

    /// Returns the path to llvm-cov tool.
    public func getLLVMCov() throws -> AbsolutePath {
        return try UserToolchain.getTool("llvm-cov", binDir: destination.binDir)
    }

    /// Returns the path to llvm-prof tool.
    public func getLLVMProf() throws -> AbsolutePath {
        return try UserToolchain.getTool("llvm-profdata", binDir: destination.binDir)
    }

    public func getSwiftAPIDigester() throws -> AbsolutePath {
        if let envValue = UserToolchain.lookup(variable: "SWIFT_API_DIGESTER", searchPaths: envSearchPaths) {
            return envValue
        }
        return try UserToolchain.getTool("swift-api-digester", binDir: swiftCompiler.parentDirectory)
    }

    public func getSymbolGraphExtract() throws -> AbsolutePath {
        if let envValue = UserToolchain.lookup(variable: "SWIFT_SYMBOLGRAPH_EXTRACT", searchPaths: envSearchPaths) {
            return envValue
        }
        return try UserToolchain.getTool("swift-symbolgraph-extract", binDir: swiftCompiler.parentDirectory)
    }

    public static func deriveSwiftCFlags(triple: Triple, destination: Destination) -> [String] {
        guard let sdk = destination.sdk else {
            if triple.isWindows() {
                // Windows uses a variable named SDKROOT to determine the root of
                // the SDK.  This is not the same value as the SDKROOT parameter
                // in Xcode, however, the value represents a similar concept.
                if let SDKROOT = ProcessEnv.vars["SDKROOT"], let root = try? AbsolutePath(validating: SDKROOT) {
                    var runtime: [String] = []
                    var xctest: [String] = []

                    if let settings = WindowsSDKSettings(reading: root.appending(component: "SDKSettings.plist"),
                                                         diagnostics: nil, filesystem: localFileSystem) {
                        switch settings.defaults.runtime {
                        case .multithreadedDebugDLL:
                            runtime = [ "-libc", "MDd" ]
                        case .multithreadedDLL:
                            runtime = [ "-libc", "MD" ]
                        case .multithreadedDebug:
                            runtime = [ "-libc", "MTd" ]
                        case .multithreaded:
                            runtime = [ "-libc", "MT" ]
                        }
                    }

                    if let DEVELOPER_DIR = ProcessEnv.vars["DEVELOPER_DIR"],
                            let root = try? AbsolutePath(validating: DEVELOPER_DIR)
                                                .appending(component: "Platforms")
                                                .appending(component: "Windows.platform") {
                        if let info = WindowsPlatformInfo(reading: root.appending(component: "Info.plist"),
                                                          diagnostics: nil, filesystem: localFileSystem) {
                            let path: AbsolutePath =
                                    root.appending(component: "Developer")
                                        .appending(component: "Library")
                                        .appending(component: "XCTest-\(info.defaults.xctestVersion)")
                            xctest = [
                                "-I", path.appending(RelativePath("usr/lib/swift/windows/\(triple.arch)")).pathString,
                                "-L", path.appending(RelativePath("usr/lib/swift/windows")).pathString,
                            ]
                        }
                    }

                    return [
                        "-sdk", root.pathString,

                        // FIXME: these should not be necessary with the `-sdk`
                        // parameter.  However, it seems that the layout on Windows
                        // is not entirely correct yet and the driver does not pick
                        // up the include search path, library search path, nor
                        // resource dir.  Workaround that for the time being to
                        // enable use of swift-package-manager on Windows.
                        "-I", root.appending(RelativePath("usr/lib/swift")).pathString,
                        "-L", root.appending(RelativePath("usr/lib/swift/windows")).pathString,
                        "-resource-dir", root.appending(RelativePath("usr/lib/swift")).pathString,
                    ] + xctest + runtime
                }
            }

            return destination.extraSwiftCFlags
        }

        return (triple.isDarwin() || triple.isAndroid() || triple.isWASI()
            ? ["-sdk", sdk.pathString]
            : [])
            + destination.extraSwiftCFlags
    }

    public init(destination: Destination, environment: [String: String] = ProcessEnv.vars) throws {
        self.destination = destination
        self.processEnvironment = environment

        // Get the search paths from PATH.
        let searchPaths = getEnvSearchPaths(
            pathString: ProcessEnv.path, currentWorkingDirectory: localFileSystem.currentWorkingDirectory)

        self.envSearchPaths = searchPaths

        // Get the binDir from destination.
        let binDir = destination.binDir

        let swiftCompilers = try UserToolchain.determineSwiftCompilers(binDir: binDir, lookup: { UserToolchain.lookup(variable: $0, searchPaths: searchPaths) }, envSearchPaths: searchPaths)
        self.swiftCompiler = swiftCompilers.compile
        self.archs = destination.archs
    
        // Use the triple from destination or compute the host triple using swiftc.
        var triple = destination.target ?? Triple.getHostTriple(usingSwiftCompiler: swiftCompilers.compile)

        // Change the triple to the specified arch if there's exactly one of them.
        // The Triple property is only looked at by the native build system currently.
        if archs.count == 1 {
            let components = triple.tripleString.drop(while: { $0 != "-" })
            triple = try Triple(archs[0] + components)
        }

        self.triple = triple

        // We require xctest to exist on macOS.
        if triple.isDarwin() {
            // FIXME: We should have some general utility to find tools.
            let xctestFindArgs = ["/usr/bin/xcrun", "--sdk", "macosx", "--find", "xctest"]
            self.xctest = try AbsolutePath(validating: Process.checkNonZeroExit(arguments: xctestFindArgs, environment: environment).spm_chomp())
        } else {
            self.xctest = nil
        }

        self.extraSwiftCFlags = UserToolchain.deriveSwiftCFlags(triple: triple, destination: destination)

        if let sdk = destination.sdk {
            self.extraCCFlags = [
                triple.isDarwin() ? "-isysroot" : "--sysroot", sdk.pathString
            ] + destination.extraCCFlags

            self.extraCPPFlags = destination.extraCPPFlags
        } else {
            self.extraCCFlags = destination.extraCCFlags
            self.extraCPPFlags = destination.extraCPPFlags
        }

        if triple.isWindows() {
            if let SDKROOT = ProcessEnv.vars["SDKROOT"], let root = try? AbsolutePath(validating: SDKROOT) {
                if let settings = WindowsSDKSettings(reading: root.appending(component: "SDKSettings.plist"),
                                                     diagnostics: nil, filesystem: localFileSystem) {
                    switch settings.defaults.runtime {
                    case .multithreadedDebugDLL:
                        // Defines _DEBUG, _MT, and _DLL
                        // Linker uses MSVCRTD.lib
                        self.extraCCFlags += ["-D_DEBUG", "-D_MT", "-D_DLL", "-Xclang", "--dependent-lib=msvcrtd"]

                    case .multithreadedDLL:
                        // Defines _MT, and _DLL
                        // Linker uses MSVCRT.lib
                        self.extraCCFlags += ["-D_MT", "-D_DLL", "-Xclang", "--dependent-lib=msvcrt"]

                    case .multithreadedDebug:
                        // Defines _DEBUG, and _MT
                        // Linker uses LIBCMTD.lib
                        self.extraCCFlags += ["-D_DEBUG", "-D_MT", "-Xclang", "--dependent-lib=libcmtd"]

                    case .multithreaded:
                        // Defines _MT
                        // Linker uses LIBCMT.lib
                        self.extraCCFlags += ["-D_MT", "-Xclang", "--dependent-lib=libcmt"]
                    }
                }
            }
        }

        // Compute the path of directory containing the PackageDescription libraries.
        var pdLibDir = UserManifestResources.libDir(forBinDir: binDir)

        // Look for an override in the env.
        if let pdLibDirEnvStr = ProcessEnv.vars["SWIFTPM_PD_LIBS"] {
            // We pick the first path which exists in an environment variable
            // delimited by the platform specific string separator.
#if os(Windows)
            let separator: Character = ";"
#else
            let separator: Character = ":"
#endif
            let paths = pdLibDirEnvStr.split(separator: separator).map(String.init)
            var foundPDLibDir = false
            for pathString in paths {
                if let path = try? AbsolutePath(validating: pathString), localFileSystem.exists(path) {
                    pdLibDir = path
                    foundPDLibDir = true
                    break
                }
            }

            if !foundPDLibDir {
                fatalError("Couldn't find any SWIFTPM_PD_LIBS directory: \(pdLibDirEnvStr)")
            }
        }

        var xctestLocation: AbsolutePath?
#if os(Windows)
        if let DEVELOPER_DIR = ProcessEnv.vars["DEVELOPER_DIR"],
                let root = try? AbsolutePath(validating: DEVELOPER_DIR)
                                    .appending(component: "Platforms")
                                    .appending(component: "Windows.platform") {
            if let info = WindowsPlatformInfo(reading: root.appending(component: "Info.plist"),
                                              diagnostics: nil, filesystem: localFileSystem) {
                xctestLocation = root.appending(component: "Developer")
                                     .appending(component: "Library")
                                     .appending(component: "XCTest-\(info.defaults.xctestVersion)")
                                     .appending(component: "usr")
                                     .appending(component: "bin")
            }
        }
#endif

        manifestResources = UserManifestResources(
            swiftCompiler: swiftCompilers.manifest,
            swiftCompilerFlags: self.extraSwiftCFlags,
            libDir: pdLibDir,
            sdkRoot: self.destination.sdk,
            xctestLocation: xctestLocation,
            // Set the bin directory if we don't have a lib dir.
            binDir: localFileSystem.exists(pdLibDir) ? nil : binDir
        )
    }
}
