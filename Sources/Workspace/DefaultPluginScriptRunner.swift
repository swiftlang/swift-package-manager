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
    let enableSandbox: Bool

    private static var _hostTriple = ThreadSafeBox<Triple>()
    private static var _packageDescriptionMinimumDeploymentTarget = ThreadSafeBox<String>()
    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    public init(cacheDir: AbsolutePath, manifestResources: ManifestResourceProvider, enableSandbox: Bool = true) {
        self.cacheDir = cacheDir
        self.resources = manifestResources
        self.enableSandbox = enableSandbox
    }

    /// Public protocol function that compiles and runs the plugin as a subprocess.  The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not of the target to which it is being applied).
    public func runPluginScript(sources: Sources, inputJSON: Data, toolsVersion: ToolsVersion, writableDirectories: [AbsolutePath], diagnostics: DiagnosticsEngine, fileSystem: FileSystem) throws -> (outputJSON: Data, stdoutText: Data) {
        let compiledExec = try self.compile(sources: sources, toolsVersion: toolsVersion, cacheDir: self.cacheDir)
        return try self.invoke(compiledExec: compiledExec, toolsVersion: toolsVersion, writableDirectories: writableDirectories, input: inputJSON)
    }
    
    public var hostTriple: Triple {
        return Self._hostTriple.memoize {
            Triple.getHostTriple(usingSwiftCompiler: resources.swiftCompiler)
        }
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
        let triple = self.hostTriple

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

    fileprivate func invoke(compiledExec: AbsolutePath, toolsVersion: ToolsVersion, writableDirectories: [AbsolutePath], input: Data) throws -> (outputJSON: Data, stdoutText: Data) {
        // Construct the command line.
        // FIXME: It would be more robust to pass it as `stdin` data, but we need TSC support for that.  When this is
        // changed, PackagePlugin will need to change as well (but no plugins need to change).
        var command = [compiledExec.pathString]
        command += [String(decoding: input, as: UTF8.self)]

        // If enabled, run command in a sandbox.
        // This provides some safety against arbitrary code execution when invoking the plugin.
        // We only allow the permissions which are absolutely necessary.
        if self.enableSandbox {
            command = Sandbox.apply(command: command, writableDirectories: writableDirectories)
        }

        // Invoke the plugin script as a subprocess.
        let result: ProcessResult
        do {
            result = try Process.popen(arguments: command)
        } catch {
            throw DefaultPluginScriptRunnerError.subprocessDidNotStart("\(error)", command: command)
        }

        // Collect the output. The `PackagePlugin` runtime library writes the output as a zero byte followed by
        // the JSON-serialized PluginEvaluationResult. Since this appears after any free-form output from the
        // script, it can be safely split out while maintaining the ability to see debug output without resorting
        // to side-channel communication that might be not be very cross-platform (e.g. pipes, file handles, etc).
        // We end up with an optional Data for the JSON, and two Datas for stdout and stderr respectively.
        var stdoutPieces = (try? result.output.get().split(separator: 0, omittingEmptySubsequences: false)) ?? []
        let jsonData = (stdoutPieces.count > 1) ? Data(stdoutPieces.removeLast()) : nil
        let stdoutData = Data(stdoutPieces.joined())
        let stderrData = (try? Data(result.stderrOutput.get())) ?? Data()
                
        // Throw an error if we the subprocess ended badly.
        if result.exitStatus != .terminated(code: 0) {
            let output = String(decoding: stdoutData + stderrData, as: UTF8.self)
            throw DefaultPluginScriptRunnerError.subprocessFailed("\(result.exitStatus)", command: command, output: output)
        }
        
        // Throw an error if we didn't get the JSON data.
        guard let json = jsonData else {
            let output = String(decoding: stdoutData + stderrData, as: UTF8.self)
            throw DefaultPluginScriptRunnerError.missingPluginJSON("didn't receive JSON output data", command: command, output: output)
        }

        // Otherwise return the JSON data and any output text.
        return (outputJSON: json, stdoutText: stdoutData + stderrData)
    }
}


/// An error encountered by the default plugin runner.
public enum DefaultPluginScriptRunnerError: Error {
    /// Failed to start running the compiled plugin script as a subprocess.  The message describes the error, and the
    /// command is the full command line that the runner tried to launch.
    case subprocessDidNotStart(_ message: String, command: [String])

    /// Running the compiled plugin script as a subprocess failed.  The message describes the error, the command is
    /// the full command line, and the output contains any emitted stdout and stderr.
    case subprocessFailed(_ message: String, command: [String], output: String)
    
    /// The compiled plugin script completed successfully, but did not emit any JSON output that could be decoded to
    /// transmit plugin information to SwiftPM.  The message describes the problem, the command is the full command
    /// line, and the output contains any emitted stdout and stderr.
    case missingPluginJSON(_ message: String, command: [String], output: String)
}

extension DefaultPluginScriptRunnerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .subprocessDidNotStart(let message, _):
            return "could not run plugin script: \(message)"
        case .subprocessFailed(let message, _, let output):
            return "running plugin script failed: \(message):\(output.isEmpty ? " (no output)" : "\n" + output)"
        case .missingPluginJSON(let message, _, let output):
            return "plugin script did not emit JSON output: \(message):\(output.isEmpty ? " (no output)" : "\n" + output)"
        }
    }
}
