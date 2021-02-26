/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageGraph
import PackageLoading // for ManifestResourceProvider
import PackageModel
import SPMBuildCore
import TSCBasic
import TSCUtility

/// A plugin script runner that compiles the plugin source files as an executable binary for the host platform, and invokes it as a subprocess.
public struct DefaultPluginScriptRunner: PluginScriptRunner {
    let cacheDir: AbsolutePath
    let resources: ManifestResourceProvider

    private static var _hostTriple = ThreadSafeBox<Triple>()
    private static var _packageDescriptionMinimumDeploymentTarget = ThreadSafeBox<String>()
    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    public init(cacheDir: AbsolutePath, manifestResources: ManifestResourceProvider) {
        self.cacheDir = cacheDir
        self.resources = manifestResources
    }

    /// Public protocol function that compiles and runs the plugin as a subprocess.  The tools version controls the availability of APIs in PackagePlugin, and should be
    public func runPluginScript(sources: Sources, inputJSON: Data, toolsVersion: ToolsVersion, diagnostics: DiagnosticsEngine, fileSystem: FileSystem) throws -> (outputJSON: Data, stdoutText: Data) {
        let compiledExec = try self.compile(sources: sources, toolsVersion: toolsVersion, cacheDir: self.cacheDir)
        return try self.invoke(compiledExec: compiledExec, input: inputJSON)
    }

    /// Helper function that compiles a plugin script as an executable and returns the path to it.
    fileprivate func compile(sources: Sources, toolsVersion: ToolsVersion, cacheDir: AbsolutePath) throws -> AbsolutePath {
        // FIXME: Much of this is copied from the ManifestLoader and should be consolidated.

        // Bin dir will be set when developing swiftpm without building all of the runtimes.
        let runtimePath = self.resources.binDir ?? self.resources.libDir

        // Compile the package plugin script.
        var command = [resources.swiftCompiler.pathString]

        // FIXME: Workaround for the module cache bug that's been haunting Swift CI
        // <rdar://problem/48443680>
        let moduleCachePath = ProcessEnv.vars["SWIFTPM_MODULECACHE_OVERRIDE"] ?? ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"]

        // If we got the binDir that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        let packageFrameworkPath = runtimePath.appending(component: "PackageFrameworks")

        let macOSPackageDescriptionPath: AbsolutePath
        if self.resources.binDir != nil, localFileSystem.exists(packageFrameworkPath) {
            command += [
                "-F", packageFrameworkPath.pathString,
                "-framework", "PackagePlugin",
                "-Xlinker", "-rpath", "-Xlinker", packageFrameworkPath.pathString,
            ]
            macOSPackageDescriptionPath = packageFrameworkPath.appending(RelativePath("PackagePlugin.framework/PackagePlugin"))
        } else {
            command += [
                "-L", runtimePath.pathString,
                "-lPackagePlugin",
            ]
            #if !os(Windows)
            // -rpath argument is not supported on Windows,
            // so we add runtimePath to PATH when executing the manifest instead
            command += ["-Xlinker", "-rpath", "-Xlinker", runtimePath.pathString]
            #endif

            // note: this is not correct for all platforms, but we only actually use it on macOS.
            macOSPackageDescriptionPath = runtimePath.appending(RelativePath("libPackagePlugin.dylib"))
        }

        // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
        #if os(macOS)
        let triple = Self._hostTriple.memoize {
            Triple.getHostTriple(usingSwiftCompiler: resources.swiftCompiler)
        }

        let version = try Self._packageDescriptionMinimumDeploymentTarget.memoize {
            (try Self.computeMinimumDeploymentTarget(of: macOSPackageDescriptionPath))?.versionString ?? "10.15"
        }
        command += ["-target", "\(triple.tripleString(forPlatformVersion: version))"]
        #endif

        // Add any extra flags required as indicated by the ManifestLoader.
        command += self.resources.swiftCompilerFlags

        command += ["-swift-version", toolsVersion.swiftLanguageVersion.rawValue]
        command += ["-I", runtimePath.pathString]
        #if os(macOS)
        if let sdkRoot = resources.sdkRoot ?? self.sdkRoot() {
            command += ["-sdk", sdkRoot.pathString]
        }
        #endif
        command += ["-package-description-version", toolsVersion.description]
        if let moduleCachePath = moduleCachePath {
            command += ["-module-cache-path", moduleCachePath]
        }

        command += sources.paths.map { $0.pathString }
        let compiledExec = cacheDir.appending(component: "compiled-plugin")
        command += ["-o", compiledExec.pathString]

        let result = try Process.popen(arguments: command)
        let output = try (result.utf8Output() + result.utf8stderrOutput()).spm_chuzzle() ?? ""
        if result.exitStatus != .terminated(code: 0) {
            // TODO: Make this a proper error.
            throw StringError("failed to compile package plugin:\n\(command)\n\n\(output)")
        }

        return compiledExec
    }

    /// Returns path to the sdk, if possible.
    // FIXME: This is copied from ManifestLoader.  This should be consolidated when ManifestLoader is cleaned up.
    private func sdkRoot() -> AbsolutePath? {
        if let sdkRoot = self.sdkRootCache.get() {
            return sdkRoot
        }

        var sdkRootPath: AbsolutePath?
        // Find SDKROOT on macOS using xcrun.
        #if os(macOS)
        let foundPath = try? Process.checkNonZeroExit(
            args: "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"
        )
        guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
            return nil
        }
        let path = AbsolutePath(sdkRoot)
        sdkRootPath = path
        self.sdkRootCache.put(path)
        #endif

        return sdkRootPath
    }

    // FIXME: This is copied from ManifestLoader.  This should be consolidated when ManifestLoader is cleaned up.
    static func computeMinimumDeploymentTarget(of binaryPath: AbsolutePath) throws -> PlatformVersion? {
        let runResult = try Process.popen(arguments: ["/usr/bin/xcrun", "vtool", "-show-build", binaryPath.pathString])
        guard let versionString = try runResult.utf8Output().components(separatedBy: "\n").first(where: { $0.contains("minos") })?.components(separatedBy: " ").last else { return nil }
        return PlatformVersion(versionString)
    }

    fileprivate func invoke(compiledExec: AbsolutePath, input: Data) throws -> (outputJSON: Data, stdoutText: Data) {
        // FIXME: It would be more robust to pass it as `stdin` data, but we need TSC support for that.  When this is
        // changed, PackagePlugin will need to change as well (but no plugins need to change).
        var command = [compiledExec.pathString]
        command += [String(decoding: input, as: UTF8.self)]
        let result = try Process.popen(arguments: command)

        // Collect the output. The `PackagePlugin` runtime library writes the output as a zero byte followed by
        // the JSON-serialized PluginEvaluationResult. Since this appears after any free-form output from the
        // script, it can be safely split out while maintaining the ability to see debug output without resorting
        // to side-channel communication that might be not be very cross-platform (e.g. pipes, file handles, etc).
        var stdoutPieces = try result.output.get().split(separator: 0, omittingEmptySubsequences: false)
        let jsonPiece = (stdoutPieces.count > 1) ? Data(stdoutPieces.removeLast()) : nil
        let stdout = Data(stdoutPieces.joined())
        let stderr = try Data(result.stderrOutput.get())
        guard let json = jsonPiece else {
            throw DefaultPluginScriptRunnerError.didNotReceiveJSONFromPlugin("didn't get any structured output from running the plugin")
        }

        // Throw an error if we failed.
        if result.exitStatus != .terminated(code: 0) {
            throw DefaultPluginScriptRunnerError.pluginSubprocessFailed("failed to invoke package plugin: \(String(decoding: stderr, as: UTF8.self))")
        }

        // Otherwise return the JSON data and any output text.
        return (outputJSON: json, stdoutText: stderr + stdout)
    }
}
public typealias DefaultExtensionRunner = DefaultPluginScriptRunner

/// An error in the default plugin runner.
public enum DefaultPluginScriptRunnerError: Swift.Error {
    case didNotReceiveJSONFromPlugin(_ message: String)
    case pluginSubprocessFailed(_ message: String)
}
