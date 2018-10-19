/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import POSIX

import Basic
import Build
import PackageLoading
import protocol Build.Toolchain
import Utility

#if os(macOS)
    private let whichClangArgs = ["xcrun", "--find", "clang"]
#else
    private let whichClangArgs = ["which", "clang"]
#endif

/// Concrete object for manifest resource provider.
public struct UserManifestResources: ManifestResourceProvider {
    public let swiftCompiler: AbsolutePath
    public let libDir: AbsolutePath
    public let sdkRoot: AbsolutePath?

    public init(
        swiftCompiler: AbsolutePath,
        libDir: AbsolutePath,
        sdkRoot: AbsolutePath? = nil
    ) {
        self.swiftCompiler = swiftCompiler
        self.libDir = libDir
        self.sdkRoot = sdkRoot
    }
}

// FIXME: This is messy and needs a redesign.
public final class UserToolchain: Toolchain {

    /// The manifest resource provider.
    public let manifestResources: ManifestResourceProvider

    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath

    /// Storage for clang compiler path.
    private var _clangCompiler: AbsolutePath?

    public let extraCCFlags: [String]

    public let extraSwiftCFlags: [String]

    public var extraCPPFlags: [String] {
        return destination.extraCPPFlags
    }

    public var dynamicLibraryExtension: String {
        return destination.dynamicLibraryExtension
    }

    /// Path of the `swift` interpreter.
    public var swiftInterpreter: AbsolutePath {
        return swiftCompiler.parentDirectory.appending(component: "swift")
    }

    /// Path to the xctest utility.
    ///
    /// This is only present on macOS.
    public let xctest: AbsolutePath?

    /// Path to llbuild.
    public let llbuild: AbsolutePath

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
                throw InvalidToolchainDiagnostic("could not find the `swiftc` at expected path \(path.asString)")
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
        let binDirCompiler = binDir.appending(component: "swiftc")
        if localFileSystem.isExecutableFile(binDirCompiler) {
            resolvedBinDirCompiler = binDirCompiler
        } else if let SWIFT_EXEC = SWIFT_EXEC {
            resolvedBinDirCompiler = SWIFT_EXEC
        } else {
            throw InvalidToolchainDiagnostic("could not find the `swiftc` at expected path \(binDirCompiler.asString)")
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (SWIFT_EXEC ?? resolvedBinDirCompiler, SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    private static func lookup(variable: String, searchPaths: [AbsolutePath]) -> AbsolutePath? {
        return lookupExecutablePath(filename: getenv(variable), searchPaths: searchPaths)
    }

    /// Environment to use when looking up tools.
    private let processEnvironment: [String: String]

    public func getClangCompiler() throws -> AbsolutePath {

        if let clangCompiler = _clangCompiler {
            return clangCompiler
        }

        let clangCompiler: AbsolutePath

        // Find the Clang compiler, looking first in the environment.
        if let value = UserToolchain.lookup(variable: "CC", searchPaths: envSearchPaths) {
            clangCompiler = value
        } else {
            // No value in env, so search for `clang`.
            let foundPath = try Process.checkNonZeroExit(arguments: whichClangArgs, environment: processEnvironment).spm_chomp()
            guard !foundPath.isEmpty else {
                throw InvalidToolchainDiagnostic("could not find `clang`")
            }
            clangCompiler = AbsolutePath(foundPath)
        }

        // Check that it's valid in the file system.
        guard localFileSystem.isExecutableFile(clangCompiler) else {
            throw InvalidToolchainDiagnostic("could not find `clang` at expected path \(clangCompiler.asString)")
        }
        _clangCompiler = clangCompiler
        return clangCompiler
    }

    public init(destination: Destination, environment: [String: String] = Process.env) throws {
        self.destination = destination
        self.processEnvironment = environment

        // Get the search paths from PATH.
        let searchPaths = getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: localFileSystem.currentWorkingDirectory)

        self.envSearchPaths = searchPaths

        // Get the binDir from destination.
        let binDir = destination.binDir

        let swiftCompilers = try UserToolchain.determineSwiftCompilers(binDir: binDir, lookup: { UserToolchain.lookup(variable: $0, searchPaths: searchPaths) })
        self.swiftCompiler = swiftCompilers.compile

        // Look for llbuild in bin dir.
        llbuild = binDir.appending(component: "swift-build-tool")
        guard localFileSystem.exists(llbuild) else {
            throw InvalidToolchainDiagnostic("could not find `llbuild` at expected path \(llbuild.asString)")
        }


        // We require xctest to exist on macOS.
      #if os(macOS)
        // FIXME: We should have some general utility to find tools.
        let xctestFindArgs = ["xcrun", "--sdk", "macosx", "--find", "xctest"]
        self.xctest = try AbsolutePath(validating: Process.checkNonZeroExit(arguments: xctestFindArgs, environment: environment).spm_chomp())
      #else
        self.xctest = nil
      #endif

        self.extraSwiftCFlags = [
            "-target", destination.target,
            "-sdk", destination.sdk.asString
        ] + destination.extraSwiftCFlags

        self.extraCCFlags = [
            "-target", destination.target,
            "--sysroot", destination.sdk.asString
        ] + destination.extraCCFlags

        // Compute the path of directory containing the PackageDescription libraries.
        let pdLibDir: AbsolutePath 
        if let pdLibDirEnvStr = getenv("SWIFTPM_PD_LIBS"), let pdLibDirEnv = try? AbsolutePath(validating: pdLibDirEnvStr) {
            pdLibDir = pdLibDirEnv
        } else {
            pdLibDir = binDir.parentDirectory.appending(components: "lib", "swift", "pm")
        }

        manifestResources = UserManifestResources(
            swiftCompiler: swiftCompilers.manifest,
            libDir: pdLibDir,
            sdkRoot: self.destination.sdk
        )
    }
}
