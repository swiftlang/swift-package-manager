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
private struct UserManifestResources: ManifestResourceProvider {
    let swiftCompiler: AbsolutePath
    let libDir: AbsolutePath
    let sdkRoot: AbsolutePath?
}

// FIXME: This is messy and needs a redesign.
public struct UserToolchain: Toolchain {

    /// The manifest resource provider.
    public let manifestResources: ManifestResourceProvider

    /// Path of the `swiftc` compiler.
    public let swiftCompiler: AbsolutePath

    /// Path of the `clang` compiler.
    public let clangCompiler: AbsolutePath

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
    let xctest: AbsolutePath?

    /// Path to llbuild.
    let llbuild: AbsolutePath

    /// The compilation destination object.
    let destination: Destination

    /// Returns the runtime library for the given sanitizer.
    func runtimeLibrary(for sanitizer: Sanitizer) throws -> AbsolutePath {
        // FIXME: This is only for SwiftPM development time support. It is OK
        // for now but we shouldn't need to resolve the symlink.  We need to lay
        // down symlinks to runtimes in our fake toolchain as part of the
        // bootstrap script.
        let swiftCompiler = resolveSymlinks(self.swiftCompiler)

        let runtime = swiftCompiler.appending(
            RelativePath("../../lib/swift/clang/lib/darwin/libclang_rt.\(sanitizer.shortName)_osx_dynamic.dylib"))

        // Ensure that the runtime is present.
        guard localFileSystem.exists(runtime) else {
            throw Error.invalidToolchain(problem: "Missing runtime for \(sanitizer) sanitizer")
        }

        return runtime
    }

    /// Determines the Swift compiler paths for compilation and manifest parsing.
    private static func determineSwiftCompilers(binDir: AbsolutePath, lookup: (String) -> AbsolutePath?) throws -> (compile: AbsolutePath, manifest: AbsolutePath) {
        func validateCompiler(at path: AbsolutePath?) throws {
            guard let path = path else { return }
            guard localFileSystem.isExecutableFile(path) else {
                throw Error.invalidToolchain(problem: "could not find the `swiftc` at expected path \(path.asString)")
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
            throw Error.invalidToolchain(problem: "could not find the `swiftc` at expected path \(binDirCompiler.asString)")
        }

        // The compiler for compilation tasks is SWIFT_EXEC or the bin dir compiler.
        // The compiler for manifest is either SWIFT_EXEC_MANIFEST or the bin dir compiler.
        return (SWIFT_EXEC ?? resolvedBinDirCompiler, SWIFT_EXEC_MANIFEST ?? resolvedBinDirCompiler)
    }

    public init(destination: Destination) throws {
        self.destination = destination

        // Get the search paths from PATH.
        let envSearchPaths = getEnvSearchPaths(
            pathString: getenv("PATH"), currentWorkingDirectory: localFileSystem.currentWorkingDirectory)

        func lookup(fromEnv: String) -> AbsolutePath? {
            return lookupExecutablePath(
                filename: getenv(fromEnv),
                searchPaths: envSearchPaths)
        }

        // Get the binDir from destination.
        let binDir = destination.binDir

        let swiftCompilers = try UserToolchain.determineSwiftCompilers(binDir: binDir, lookup: lookup(fromEnv:))
        self.swiftCompiler = swiftCompilers.compile

        // Look for llbuild in bin dir.
        llbuild = binDir.appending(component: "swift-build-tool")
        guard localFileSystem.exists(llbuild) else {
            throw Error.invalidToolchain(problem: "could not find `llbuild` at expected path \(llbuild.asString)")
        }

        // Find the Clang compiler, looking first in the environment.
        if let value = lookup(fromEnv: "CC") {
            clangCompiler = value
        } else {
            // No value in env, so search for `clang`.
            let foundPath = try Process.checkNonZeroExit(arguments: whichClangArgs).chomp()
            guard !foundPath.isEmpty else {
                throw Error.invalidToolchain(problem: "could not find `clang`")
            }
            clangCompiler = AbsolutePath(foundPath)
        }

        // Check that it's valid in the file system.
        guard localFileSystem.isExecutableFile(clangCompiler) else {
            throw Error.invalidToolchain(problem: "could not find `clang` at expected path \(clangCompiler.asString)")
        }

        // We require xctest to exist on macOS.
      #if os(macOS)
        // FIXME: We should have some general utility to find tools.
        let xctestFindArgs = ["xcrun", "--sdk", "macosx", "--find", "xctest"]
        self.xctest = try AbsolutePath(validating: Process.checkNonZeroExit(arguments: xctestFindArgs).chomp())
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

        manifestResources = UserManifestResources(
            swiftCompiler: swiftCompilers.manifest,
            libDir: binDir.parentDirectory.appending(components: "lib", "swift", "pm"),
            sdkRoot: self.destination.sdk
        )
    }
}
