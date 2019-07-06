/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic
import Build
import PackageLoading
import protocol Build.Toolchain
import SPMUtility

#if os(macOS)
private let whichArgs: [String] = ["xcrun", "--find"]
#else
private let whichArgs = ["which"]
#endif
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

    public let extraCCFlags: [String]

    public let extraSwiftCFlags: [String]

    public var extraCPPFlags: [String] {
        return destination.extraCPPFlags
    }

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

    /// Determines the Swift compiler paths for compilation and manifest parsing.
    private static func determineSwiftCompilers(binDir: AbsolutePath, lookup: (String) -> AbsolutePath?) throws -> (compile: AbsolutePath, manifest: AbsolutePath) {
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
        let binDirCompiler = binDir.appending(component: "swiftc" + hostExecutableSuffix)
        if localFileSystem.isExecutableFile(binDirCompiler) {
            resolvedBinDirCompiler = binDirCompiler
        } else if let SWIFT_EXEC = SWIFT_EXEC {
            resolvedBinDirCompiler = SWIFT_EXEC
        } else {
            throw InvalidToolchainDiagnostic("could not find the `swiftc\(hostExecutableSuffix)` at expected path \(binDirCompiler)")
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (SWIFT_EXEC ?? resolvedBinDirCompiler, SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    private static func lookup(variable: String, searchPaths: [AbsolutePath]) -> AbsolutePath? {
        return lookupExecutablePath(filename: Process.env[variable], searchPaths: searchPaths)
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
            let toolPath = destination.binDir.appending(component: "clang" + hostExecutableSuffix)
            if localFileSystem.exists(toolPath) {
                _clangCompiler = toolPath
                return toolPath
            }
        }

        // Otherwise, lookup it up on the system.
        let arguments = whichArgs + ["clang"]
        let foundPath = try Process.checkNonZeroExit(arguments: arguments, environment: processEnvironment).spm_chomp()
        guard !foundPath.isEmpty else {
            throw InvalidToolchainDiagnostic("could not find clang")
        }
        let toolPath = try AbsolutePath(validating: foundPath)
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
        let toolPath = destination.binDir.appending(component: "llvm-cov")
        guard localFileSystem.isExecutableFile(toolPath) else {
            throw InvalidToolchainDiagnostic("could not find llvm-cov at expected path \(toolPath)")
        }
        return toolPath
    }

    /// Returns the path to llvm-prof tool.
    public func getLLVMProf() throws -> AbsolutePath {
        let toolPath = destination.binDir.appending(component: "llvm-profdata")
        guard localFileSystem.isExecutableFile(toolPath) else {
            throw InvalidToolchainDiagnostic("could not find llvm-profdata at expected path \(toolPath)")
        }
        return toolPath
    }

    public init(destination: Destination, environment: [String: String] = Process.env) throws {
        self.destination = destination
        self.processEnvironment = environment

        // Get the search paths from PATH.
        let searchPaths = getEnvSearchPaths(
            pathString: Process.env["PATH"], currentWorkingDirectory: localFileSystem.currentWorkingDirectory)

        self.envSearchPaths = searchPaths

        // Get the binDir from destination.
        let binDir = destination.binDir

        let swiftCompilers = try UserToolchain.determineSwiftCompilers(binDir: binDir, lookup: { UserToolchain.lookup(variable: $0, searchPaths: searchPaths) })
        self.swiftCompiler = swiftCompilers.compile

        // We require xctest to exist on macOS.
      #if os(macOS)
        // FIXME: We should have some general utility to find tools.
        let xctestFindArgs = ["xcrun", "--sdk", "macosx", "--find", "xctest"]
        self.xctest = try AbsolutePath(validating: Process.checkNonZeroExit(arguments: xctestFindArgs, environment: environment).spm_chomp())
      #else
        self.xctest = nil
      #endif

        self.extraSwiftCFlags = [
            "-sdk", destination.sdk.pathString
        ] + destination.extraSwiftCFlags

        self.extraCCFlags = [
            destination.target.isDarwin() ? "-isysroot" : "--sysroot", destination.sdk.pathString
        ] + destination.extraCCFlags

        // Compute the path of directory containing the PackageDescription libraries.
        let manifestBinDir = swiftCompilers.manifest.parentDirectory
        var pdLibDir = UserManifestResources.libDir(forBinDir: manifestBinDir)

        // Look for an override in the env.
        if let pdLibDirEnvStr = Process.env["SWIFTPM_PD_LIBS"] {
            // We pick the first path which exists in a colon seperated list.
            let paths = pdLibDirEnvStr.split(separator: ":").map(String.init)
            for pathString in paths {
                if let path = try? AbsolutePath(validating: pathString), localFileSystem.exists(path) {
                    pdLibDir = path
                    break
                }
            }
        }

        manifestResources = UserManifestResources(
            swiftCompiler: swiftCompilers.manifest,
            libDir: pdLibDir,
            sdkRoot: self.destination.sdk
        )
    }
}
