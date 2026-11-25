//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SwiftPMInternal)
import Basics

import Foundation
import PackageGraph
import PackageModel

import struct TSCBasic.ByteString
import class Basics.AsyncProcess

import struct TSCUtility.SerializedDiagnostics

// SPMBuildCore is an exported target, so its Subprocess and System dependencies must not leak into the module's
// required modules (see Basics/Archiver/ZipArchiver.swift). Subprocess types therefore only appear in function bodies and
// in non-public declarations in this file.
#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Subprocess
#if canImport(System)
@_implementationOnly import System
#else
@_implementationOnly import SystemPackage
#endif
#else
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif
#endif

#if os(Android)
import Android
#endif

/// A plugin script runner that compiles the plugin source files as an executable binary for the host platform, and invokes it as a subprocess.
public struct DefaultPluginScriptRunner: PluginScriptRunner, Cancellable {
    private let fileSystem: FileSystem
    private let cacheDir: Basics.AbsolutePath
    private let toolchain: any Toolchain
    private let extraPluginSwiftCFlags: [String]
    private let enableSandbox: Bool
    private let cancellator: Cancellator
    private let verboseOutput: Bool

    private let sdkRootCache = ThreadSafeBox<Basics.AbsolutePath?>()

    public init(
        fileSystem: Basics.FileSystem,
        cacheDir: Basics.AbsolutePath,
        toolchain: any Toolchain,
        extraPluginSwiftCFlags: [String] = [],
        enableSandbox: Bool = true,
        verboseOutput: Bool = false
    ) {
        self.fileSystem = fileSystem
        self.cacheDir = cacheDir
        self.toolchain = toolchain
        self.extraPluginSwiftCFlags = extraPluginSwiftCFlags
        self.enableSandbox = enableSandbox
        self.cancellator = Cancellator(observabilityScope: .none)
        self.verboseOutput = verboseOutput
    }

    /// Starts evaluating a plugin by compiling it and running it as a subprocess. The name is used as the basename for the executable and auxiliary files.  The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not the package containing the target to which it is being applied). This function returns immediately and then repeated calls the output handler on the given callback queue as plain-text output is received from the plugin, and then eventually calls the completion handler on the given callback queue once the plugin is done.
    public func runPluginScript(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: Basics.AbsolutePath,
        writableDirectories: [Basics.AbsolutePath],
        readOnlyDirectories: [Basics.AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        workers: UInt32,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate & PluginScriptRunnerDelegate
    ) async throws -> Int32 {
        // If needed, compile the plugin script to an executable. Compilation is skipped if the plugin hasn't changed since it was last compiled.
        let result = try await self.compilePluginScript(
            sourceFiles: sourceFiles,
            pluginName: pluginName,
            toolsVersion: toolsVersion,
            workers: workers,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue.sharedConcurrent,
            delegate: delegate
        )
        guard result.succeeded else {
            // Compilation failed, so throw an error.
            throw DefaultPluginScriptRunnerError.compilationFailed(result)
        }

        // Compilation succeeded, so run the executable.
        return try await self.invoke(
            compiledExec: result.executableFile,
            workingDirectory: workingDirectory,
            writableDirectories: writableDirectories,
            readOnlyDirectories: readOnlyDirectories,
            allowNetworkConnections: allowNetworkConnections,
            initialMessage: initialMessage,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            delegate: delegate
        )
    }

    public var hostTriple: Triple {
        return self.toolchain.targetTriple
    }

    public func buildCommandLine(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope?
    ) -> (commandLine: [String], execName: String, execFilePath: AbsolutePath, diagFilePath: AbsolutePath) {
        // Determine the path of the executable and other produced files.
        let execName = pluginName.spm_mangledToC99ExtendedIdentifier()
        #if os(Windows)
        let execSuffix = ".exe"
        #else
        let execSuffix = ""
        #endif
        let execFilePath = self.cacheDir.appending(component: execName + execSuffix)
        let diagFilePath = self.cacheDir.appending(component: execName + ".dia")
        observabilityScope?.emit(debug: "Compiling plugin to executable at \(execFilePath)")

        // Construct the command line for compiling the plugin script(s).
        // FIXME: Much of this is similar to what the ManifestLoader is doing. This should be consolidated.

        // We use the toolchain's Swift compiler for compiling the plugin.
        var commandLine = [self.toolchain.swiftCompilerPathForManifests.pathString]

        observabilityScope?.emit(debug: "Using compiler \(self.toolchain.swiftCompilerPathForManifests.pathString)")

        // Get access to the path containing the PackagePlugin module and library.
        let pluginLibraryPath = self.toolchain.swiftPMLibrariesLocation.pluginLibraryPath
        let pluginModulesPath = self.toolchain.swiftPMLibrariesLocation.pluginModulesPath

        // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        if pluginLibraryPath.extension == "framework" {
            let parent = pluginLibraryPath.parentDirectory
            commandLine += [
                "-F", parent.pathString,
                "-framework", "PackagePlugin",
                "-Xlinker", "-rpath", "-Xlinker", parent.pathString,
            ]

            // Make sure we can find the swiftmodule
            if parent.basename == "PackageFrameworks" {
                commandLine += ["-I", parent.parentDirectory.pathString]
            } else {
                commandLine += ["-I", parent.pathString]
            }
        } else {
            commandLine += [
                "-L", pluginLibraryPath.pathString,
                "-lPackagePlugin",
            ]
            #if !os(Windows)
            // -rpath argument is not supported on Windows,
            // so we add runtimePath to PATH when executing the manifest instead
            commandLine += ["-Xlinker", "-rpath", "-Xlinker", pluginLibraryPath.pathString]
            #endif
        }

        #if os(macOS)
        // On macOS earlier than 12, add an rpath to the directory that contains the concurrency fallback library.
        if #available(macOS 12.0, *) {
            // Nothing is needed; the system has everything we need.
        }
        else {
            // Add an `-rpath` so the Swift 5.5 fallback libraries can be found.
            let swiftSupportLibPath = self.toolchain.swiftCompilerPathForManifests.parentDirectory.parentDirectory.appending(components: "lib", "swift-5.5", "macosx")
            commandLine += ["-Xlinker", "-rpath", "-Xlinker", swiftSupportLibPath.pathString]
        }
        #endif

        // Use the same minimum deployment target as the PackagePlugin library (with a fallback to the default host triple).
        #if os(macOS)
        if let version = self.toolchain.swiftPMLibrariesLocation.pluginLibraryMinimumDeploymentTarget?.versionString {
            commandLine += ["-target", "\(self.toolchain.targetTriple.tripleString(forPlatformVersion: version))"]
        } else {
            commandLine += ["-target", self.toolchain.targetTriple.tripleString]
        }
        #endif

        // Add any extra flags required as indicated by the ManifestLoader.
        commandLine += self.toolchain.swiftCompilerFlags

        commandLine.append("-g")

        // Add the Swift language version implied by the package tools version.
        commandLine += ["-swift-version", toolsVersion.swiftLanguageVersion.rawValue]

        // Add the PackageDescription version specified by the package tools version, which controls what PackagePlugin API is seen.
        commandLine += ["-package-description-version", toolsVersion.description]

        // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
        // which produces a framework for dynamic package products.
        if pluginModulesPath.extension == "framework" {
            commandLine += ["-I", pluginModulesPath.parentDirectory.parentDirectory.pathString]
        } else {
            commandLine += ["-I", pluginModulesPath.pathString]
        }
        #if os(macOS)
        if let sdkRoot = self.toolchain.sdkRootPath ?? self.sdkRoot() {
            commandLine += ["-sdk", sdkRoot.pathString]
        }
        #endif

        // Honor any module cache override that's set in the environment.
        let moduleCachePath = Environment.current["SWIFTPM_MODULECACHE_OVERRIDE"] ?? Environment.current["SWIFTPM_TESTS_MODULECACHE"]
        if let moduleCachePath {
            commandLine += ["-module-cache-path", moduleCachePath]
        }

        // Parse the plugin as a library so that `@main` is supported even though there might be only a single source file.
        commandLine += ["-parse-as-library"]

        // Enable concurrent compilation.
        commandLine += ["-j\(workers)"]

        // Ask the compiler to create a diagnostics file (we'll put it next to the executable).
        commandLine += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagFilePath.pathString]

        // Add all the source files that comprise the plugin scripts.
        commandLine += sourceFiles.map { $0.pathString }

        // Finally add the output path of the compiled executable.
        commandLine += ["-o", execFilePath.pathString]

        // Add any extra flags passed for the host in the command line
        commandLine += self.extraPluginSwiftCFlags

        if (verboseOutput) {
            commandLine.append("-v")
        }
        return (commandLine, execName, execFilePath, diagFilePath)
    }

    /// Compiles a plugin script and returns the results (including the path of the compiled plugin executable and any emitted diagnostics, etc). Existing compilation results that are still valid are reused, if possible. Note that this only throws if the compiler couldn't be invoked at all; a non-zero exit code from the compiler still returns a full compilation result that notes the error in the diagnostics.
    public func compilePluginScript(
        sourceFiles: [Basics.AbsolutePath],
        pluginName: String,
        toolsVersion: ToolsVersion,
        workers: UInt32,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptCompilerDelegate
    ) async throws -> PluginCompilationResult {
        let (commandLine, execName, execFilePath, diagFilePath) = self.buildCommandLine(
            sourceFiles: sourceFiles,
            pluginName: pluginName,
            toolsVersion: toolsVersion,
            workers: workers,
            observabilityScope: observabilityScope
        )

        // Pass through the compilation environment.
        let environment = toolchain.swiftCompilerEnvironment

        // First try to create the output directory.
        do {
            observabilityScope.emit(debug: "Plugin compilation output directory '\(execFilePath.parentDirectory)'")
            try FileManager.default.createDirectory(at: execFilePath.parentDirectory.asURL, withIntermediateDirectories: true, attributes: nil)
        }
        catch {
            // Bail out right away if we didn't even get this far.
            throw DefaultPluginScriptRunnerError.compilationPreparationFailed(error: error)
        }

        // Hash the compiler inputs to decide whether we really need to recompile.
        let compilerInputHash: String?
        do {
            // Include the full compiler arguments and environment, and the contents of the source files.
            var stringToHash = commandLine.description
            for (key, value) in toolchain.swiftCompilerEnvironment.sorted(by: { $0.key < $1.key }) {
                stringToHash.append("\(key)=\(value)\n")
            }
            for sourceFile in sourceFiles {
                let source: String = try fileSystem.readFileContents(sourceFile)
                stringToHash.append(source)
            }
            compilerInputHash = ByteString(encodingAsUTF8: stringToHash).sha256Checksum
            observabilityScope.emit(debug: "Computed hash of plugin compilation inputs: \(compilerInputHash!)")
        }
        catch {
            // We couldn't compute the hash. We warn about it but proceed with the compilation (a cache miss).
            observabilityScope.emit(debug: "Couldn't compute hash of plugin compilation inputs", underlyingError: error)
            compilerInputHash = .none
        }

        /// Persisted information about the last time the compiler was invoked.
        struct PersistedCompilationState: Codable {
            var commandLine: [String]
            var environment: Basics.Environment
            var inputHash: String?
            var output: String
            var result: Result
            enum Result: Equatable, Codable {
                case exit(code: Int32)
                case abnormal(exception: UInt32)
                case signal(number: Int32)

                init(_ terminationStatus: Subprocess.TerminationStatus) {
                    switch terminationStatus {
                    case .exited(let code):
                        #if os(Windows)
                        self = .exit(code: Int32(bitPattern: code))
                        #else
                        self = .exit(code: code)
                        #endif
                    #if !os(Windows)
                    case .signaled(let signal):
                        self = .signal(number: signal)
                    #endif
                    }
                }
            }

            var succeeded: Bool {
                return result == .exit(code: 0)
            }
        }

        // Check if we already have a compiled executable and a persisted state (we only recompile if things have changed).
        let stateFilePath = self.cacheDir.appending(component: execName + "-state" + ".json")
        var compilationState: PersistedCompilationState? = .none
        if fileSystem.exists(execFilePath) && fileSystem.exists(stateFilePath) {
            do {
                // Try to load the previous compilation state.
                let previousState = try JSONDecoder.makeWithDefaults().decode(
                    path: stateFilePath,
                    fileSystem: fileSystem,
                    as: PersistedCompilationState.self)

                // If it succeeded last time and the compiler inputs are the same, we don't need to recompile.
                if previousState.succeeded && previousState.inputHash == compilerInputHash {
                    compilationState = previousState
                }
            }
            catch {
                // We couldn't read the compilation state file even though it existed. We warn about it but proceed with recompiling.
                observabilityScope.emit(debug: "Couldn't read previous compilation state", underlyingError: error)
            }
        }

        // If we still have a compilation state, it means the executable is still valid and we don't need to do anything.
        if let compilationState {
            // Return the persisted results.
            let result = PluginCompilationResult(
                succeeded: compilationState.succeeded,
                commandLine: commandLine,
                executableFile: execFilePath,
                diagnosticsFile: diagFilePath,
                compilerOutput: compilationState.output,
                cached: true)
            delegate.skippedCompilingPlugin(cachedResult: result)
            return result
        }

        // Otherwise we need to recompile. We start by telling the delegate.
        delegate.willCompilePlugin(commandLine: commandLine, environment: .init(environment))

        // Clean up any old files to avoid confusion if the compiler can't be invoked.
        do {
            try fileSystem.removeFileTree(execFilePath)
            try fileSystem.removeFileTree(diagFilePath)
            try fileSystem.removeFileTree(stateFilePath)
        }
        catch {
            observabilityScope.emit(debug: "Couldn't clean up before invoking compiler", underlyingError: error)
        }

        // Now invoke the compiler.
        let compilerEnvironment = Subprocess.Environment.custom(filtering: environment)
        let compilerCommandLine = commandLine
        let runCompiler: @Sendable () async throws -> (output: [UInt8], error: [UInt8], status: TerminationStatus) = {
            let result = try await Subprocess.run(
                .path(FilePath(compilerCommandLine[0])),
                arguments: Subprocess.Arguments(Array(compilerCommandLine.dropFirst())),
                environment: compilerEnvironment,
                output: .bytes(limit: .max),
                error: .bytes(limit: .max)
            )
            return (result.standardOutput, result.standardError, result.terminationStatus)
        }
        #if os(Windows)
        // Cancelling the calling task would make Subprocess force-terminate the compiler. On Windows a compiler
        // terminated while it builds an implicit module leaves the module's lock file behind, and LLVM's
        // `LockFileManager` can't tell that the lock's owner has exited, so every later compiler that needs the module
        // waits for the lock to time out. Run the compiler detached from the caller's cancellation instead, and let it
        // finish.
        let compilation = try await Task.detached(operation: runCompiler).value
        #else
        let compilation = try await runCompiler()
        #endif

        // Always show compiler output on failure, but only show successful
        // compiler output at verbose log levels.
        let compilerOutput = String(decoding: compilation.output, as: UTF8.self)
            + String(decoding: compilation.error, as: UTF8.self)
        if !compilerOutput.isEmpty {
            observabilityScope.print(
                compilerOutput,
                condition: compilation.status.isSuccess
                    ? .onlyWhenVerbose
                    : .always
            )
        }

        // Save the persisted compilation state for possible reuse next time.
        let newCompilationState = PersistedCompilationState(
            commandLine: commandLine,
            environment: toolchain.swiftCompilerEnvironment.cachable,
            inputHash: compilerInputHash,
            output: compilerOutput,
            result: .init(compilation.status))
        do {
            try JSONEncoder.makeWithDefaults().encode(path: stateFilePath, fileSystem: self.fileSystem, newCompilationState)
        }
        catch {
            // We couldn't write out the `.state` file. We warn about it but proceed.
            observabilityScope.emit(debug: "Couldn't save plugin compilation state", underlyingError: error)
        }

        // Construct a PluginCompilationResult for both the successful and unsuccessful cases (to convey diagnostics, etc).
        let result = PluginCompilationResult(
            succeeded: newCompilationState.succeeded,
            commandLine: commandLine,
            executableFile: execFilePath,
            diagnosticsFile: diagFilePath,
            compilerOutput: compilerOutput,
            cached: false)

        // Tell the delegate that we're done compiling the plugin, passing it the result.
        delegate.didCompilePlugin(result: result)

        // Also return the result to the caller.
        return result
    }

    /// Returns path to the sdk, if possible.
    // FIXME: This is copied from ManifestLoader.  This should be consolidated when ManifestLoader is cleaned up.
    private func sdkRoot() -> Basics.AbsolutePath? {
        return self.sdkRootCache.memoizeOptional(body: {
            var sdkRootPath: Basics.AbsolutePath?
            // Find SDKROOT on macOS using xcrun.
            #if os(macOS)
            let foundPath = try? AsyncProcess.checkNonZeroExit(
                args: "/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"
            )
            guard let sdkRoot = foundPath?.spm_chomp(), !sdkRoot.isEmpty else {
                return nil
            }
            if let path = try? Basics.AbsolutePath(validating: sdkRoot) {
                sdkRootPath = path
            }
            #endif

            return sdkRootPath
        })
    }
    
    /// Private function that invokes a compiled plugin executable and communicates with it until it finishes.
    fileprivate func invoke(
        compiledExec: Basics.AbsolutePath,
        workingDirectory: Basics.AbsolutePath,
        writableDirectories: [Basics.AbsolutePath],
        readOnlyDirectories: [Basics.AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        initialMessage: Data,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptRunnerDelegate
    ) async throws -> Int32 {
#if canImport(Darwin) && !os(macOS)
        throw DefaultPluginScriptRunnerError.pluginUnavailable(reason: "subprocess invocations are unavailable on this platform")
#else
        // Construct the command line. Currently we just invoke the executable built from the plugin without any parameters.
        var command = [compiledExec.pathString]

        // Optionally wrap the command in a sandbox, which places some limits on what it can do. In particular, it blocks network access and restricts the paths to which the plugin can make file system changes. It does allow writing to temporary directories.
        if self.enableSandbox {
            command = try Sandbox.apply(
                command: command,
                fileSystem: self.fileSystem,
                strictness: .writableTemporaryDirectory,
                writableDirectories: writableDirectories + [self.cacheDir],
                readOnlyDirectories: readOnlyDirectories,
                allowNetworkConnections: allowNetworkConnections
            )
        }

        // Build the environment for the plugin process.
        var env = Basics.Environment.current

        // FIXME: This is largely a workaround for improper rpath setup on Linux. It should be
        // removed once the Swift Build backend switches to use swiftc as the linker driver
        // for targets with Swift sources. For now, limit the scope to non-macOS, so that
        // plugins do not inadvertently use the toolchain stdlib instead of the OS stdlib
        // when built with a Swift.org toolchain.
        #if !os(macOS)
        // Update the environment for any runtime library paths that tools compiled
        // for the command plugin might require after they have been built.
        let runtimeLibPaths = self.toolchain.runtimeLibraryPaths
        for libPath in runtimeLibPaths {
            env.appendPath(key: .libraryPath, value: libPath.pathString)
        }
        #endif

#if os(Windows)
        let pluginLibraryPath = self.toolchain.swiftPMLibrariesLocation.pluginLibraryPath.pathString
        env.prependPath(key: .path, value: pluginLibraryPath)
#endif
        let subprocessEnvironment = Subprocess.Environment.custom(filtering: env)

        // Accumulate the plugin's free-form stderr output so it can be included in errors.
        let stderrData = ThreadSafeBox<Data>(Data())

        // Run the plugin executable as a subprocess, communicating over the duplex message protocol on
        // its stdin/stdout and capturing free-form text on its stderr. Running through the cancellator
        // means an interrupted host asks the plugin (and anything it started) to stop before it is terminated.
        let terminationStatus: TerminationStatus
        do {
            terminationStatus = try await self.cancellator.withCancellable(name: command.joined(separator: " ")) {
                let outcome = try await Subprocess.run(
                    .path(FilePath(command[0])),
                    arguments: Subprocess.Arguments(Array(command.dropFirst())),
                    environment: subprocessEnvironment,
                    workingDirectory: FilePath(workingDirectory.pathString),
                    platformOptions: .cancellablePluginRun,
                    input: .inputWriter,
                    output: .sequence,
                    error: .sequence
                ) { execution in
                    let writer = execution.standardInputWriter

                    // Send the initial message to the plugin. If the plugin has already exited (for example because it
                    // failed to load), the write fails; carry on so that its exit status and stderr are reported
                    // instead of an opaque I/O error.
                    _ = try? await writer.write(framePluginMessage(initialMessage))

                    try await withThrowingTaskGroup(of: Void.self) { group in
                        // Receive length-delimited messages on stdout, handle each, and send any replies.
                        group.addTask {
                            var decoder = PluginMessageDecoder()
                            for try await chunk in execution.standardOutput {
                                let messages: [Data]
                                do {
                                    messages = try chunk.withUnsafeBytes { try decoder.push($0) }
                                } catch {
                                    throw DefaultPluginScriptRunnerError.pluginCommunicationError(
                                        message: "\(error)",
                                        command: command,
                                        output: String(decoding: stderrData.get(), as: UTF8.self)
                                    )
                                }
                                for messageData in messages {
                                    do {
                                        if let reply = try await delegate.handleMessage(data: messageData) {
                                            _ = try? await writer.write(framePluginMessage(reply))
                                        }
                                    }
                                    catch DecodingError.keyNotFound(let key, _) where key.stringValue == "version" {
                                        print("message from plugin did not contain a 'version' key, likely an incompatible plugin library is being loaded by the plugin")
                                    }
                                    catch {
                                        print("error while trying to handle message from plugin: \(error.interpolationDescription)")
                                    }
                                }
                            }
                            // The plugin closed its stdout, so it won't read any more replies.
                            try? await writer.finish()
                        }

                        // Receive free-form text output on stderr and pass it on to the delegate.
                        group.addTask {
                            for try await chunk in execution.standardError {
                                let data = chunk.withUnsafeBytes { Data($0) }
                                if data.isEmpty { continue }
                                stderrData.mutate { $0.append(data) }
                                callbackQueue.async { delegate.handleOutput(data: data) }
                            }
                        }

                        try await group.waitForAll()
                    }
                }
                return outcome.terminationStatus
            }
        } catch let error as DefaultPluginScriptRunnerError {
            throw error
        } catch let error as Basics.CancellationError {
            throw error
        } catch let error as _Concurrency.CancellationError {
            throw error
        } catch {
            // The plugin couldn't be started (or the run failed in a way that has no more specific error).
            throw DefaultPluginScriptRunnerError.invocationFailed(error: error, command: command)
        }

        // Return a result that depends on how the process ended. We report an error if it ended with a signal.
        switch terminationStatus {
        case .exited(let code):
            #if os(Windows)
            return Int32(bitPattern: code)
            #else
            return code
            #endif
        #if !os(Windows)
        case .signaled(let signal):
            throw DefaultPluginScriptRunnerError.invocationEndedBySignal(
                signal: signal,
                command: command,
                output: String(decoding: stderrData.get(), as: UTF8.self))
        #endif
        }
#endif
    }

    public func cancel(deadline: DispatchTime) throws {
        try self.cancellator.cancel(deadline: deadline)
    }
}

/// An error encountered by the default plugin runner.
public enum DefaultPluginScriptRunnerError: Error, CustomStringConvertible {
    /// The plugin is not available for some reason.
    case pluginUnavailable(reason: String)

    /// An error occurred while preparing to compile the plugin script.
    case compilationPreparationFailed(error: Error)

    /// An error occurred while compiling the plugin script (e.g. syntax error).
    /// The diagnostics are available in the plugin compilation result.
    case compilationFailed(PluginCompilationResult)

    /// The plugin invocation couldn't be started.
    case invocationFailed(error: Error, command: [String])

    /// The plugin invocation ended by a signal.
    case invocationEndedBySignal(signal: Int32, command: [String], output: String)

    /// The plugin invocation ended with a non-zero exit code.
    case invocationEndedWithNonZeroExitCode(exitCode: Int32, command: [String], output: String)

    /// There was an error communicating with the plugin.
    case pluginCommunicationError(message: String, command: [String], output: String)

    public var description: String {
        func makeContextString(_ command: [String], _ output: String) -> String {
            return "<command: \(command.map{ $0.spm_shellEscaped() }.joined(separator: " "))>, <output:\n\(output.spm_shellEscaped())>"
        }
        switch self {
        case .pluginUnavailable(let reason):
            return "plugin is unavailable: \(reason)"
        case .compilationPreparationFailed(let error):
            return "plugin compilation preparation failed: \(error.interpolationDescription)"
        case .compilationFailed(let result):
            return "plugin compilation failed: \(result)"
        case .invocationFailed(let error, let command):
            return "plugin invocation failed: \(error.interpolationDescription) \(makeContextString(command, ""))"
        case .invocationEndedBySignal(let signal, let command, let output):
            return "plugin process ended by an uncaught signal: \(signal) \(makeContextString(command, output))"
        case .invocationEndedWithNonZeroExitCode(let exitCode, let command, let output):
            return "plugin process ended with a non-zero exit code: \(exitCode) \(makeContextString(command, output))"
        case .pluginCommunicationError(let message, let command, let output):
            return "plugin communication error: \(message) \(makeContextString(command, output))"
        }
    }
}

/// Frames a plugin message for sending: a 64-bit little-endian length header followed by the payload.
package func framePluginMessage(_ message: Data) -> [UInt8] {
    var length = UInt64(message.count).littleEndian
    var bytes = [UInt8]()
    bytes.reserveCapacity(8 + message.count)
    Swift.withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
    bytes.append(contentsOf: message)
    return bytes
}

/// An error found while decoding the plugin message stream.
package enum PluginMessageDecoderError: Error, CustomStringConvertible {
    /// A message header declared a payload size that is too small or too large to be valid.
    case invalidPayloadSize(UInt64)

    package var description: String {
        switch self {
        case .invalidPayloadSize(let size):
            return "invalid message payload size \(size)"
        }
    }
}

/// Reassembles length-delimited plugin messages from a stream of arbitrarily-chunked bytes.
///
/// Each message is a 64-bit little-endian length header followed by that many payload bytes. Bytes are
/// buffered across `push` calls so a message that spans multiple chunks (or several messages arriving in
/// one chunk) is decoded correctly.
package struct PluginMessageDecoder {
    /// The smallest valid payload (an empty JSON object has two bytes).
    package static let minimumPayloadSize: UInt64 = 2
    /// The largest payload accepted, so that a corrupt header can't make the decoder buffer without bound.
    package static let maximumPayloadSize = UInt64(Int32.max)

    private var buffer = [UInt8]()

    package init() {}

    /// Appends `bytes` to the internal buffer and returns every complete message that can now be decoded.
    ///
    /// - Throws: `PluginMessageDecoderError.invalidPayloadSize` if a header declares an implausible size.
    package mutating func push(_ bytes: UnsafeRawBufferPointer) throws -> [Data] {
        self.buffer.append(contentsOf: bytes)

        var messages = [Data]()
        var start = 0
        defer { self.buffer.removeFirst(start) }
        while self.buffer.count - start >= 8 {
            // Decode the 64-bit little-endian length header.
            var length: UInt64 = 0
            for index in 0..<8 {
                length |= UInt64(self.buffer[start + index]) << (8 * UInt64(index))
            }
            guard length >= Self.minimumPayloadSize, length <= Self.maximumPayloadSize else {
                throw PluginMessageDecoderError.invalidPayloadSize(length)
            }

            let total = 8 + Int(length)
            // Wait for the full payload before yielding the message.
            guard self.buffer.count - start >= total else { break }

            messages.append(Data(self.buffer[(start + 8)..<(start + total)]))
            start += total
        }
        return messages
    }
}

extension Subprocess.Environment {
    /// Creates a custom environment from `environment`, leaving out the entries swift-subprocess would reject
    /// (and so fail every spawn), such as variables whose names start with a digit.
    static func custom(filtering environment: Basics.Environment) -> Self {
        .custom(Dictionary(
            environment.removingKeysInvalidForSubprocess.compactMap { entry in
                Subprocess.Environment.Key(rawValue: entry.key.rawValue).map { ($0, entry.value) }
            },
            uniquingKeysWith: { _, last in last }
        ))
    }
}

extension Subprocess.PlatformOptions {
    /// Options for a child process run through `Cancellator.withCancellable`.
    ///
    /// Without these, cancelling terminates only the direct child with an immediate `SIGKILL`: descendants (for example
    /// the tools a plugin started) survive, and the child gets no chance to clean up. This puts the child in its own
    /// process group and tears the whole group down gracefully before force-terminating it.
    ///
    /// - Parameter gracePeriod: How long each graceful step waits for the process to exit before moving on to the next
    ///   step and, finally, force-terminating the whole group.
    ///
    /// Keep in sync with the copies in `Basics/Concurrency/CancellablePlatformOptions.swift` and
    /// `SwiftTestCommand.swift`.
    static func cancellable(gracePeriod: Duration = .seconds(2)) -> Self {
        var options = Self()
        #if os(Windows)
        options.createProcessGroup = true
        options.teardownSequence = [.gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: gracePeriod)]
        #else
        options.processGroupID = 0
        options.teardownSequence = [
            .send(signal: .interrupt, toProcessGroup: true, allowedDurationToNextStep: gracePeriod),
        ]
        #endif
        return options
    }

    /// Options for running a plugin.
    ///
    /// A plugin can run builds, so its descendants may be compilers. On Windows, force-terminating a compiler that is
    /// building an implicit module leaves the module's lock file behind, and because LLVM's `LockFileManager` can't tell
    /// that the lock's owner has exited there, every later compiler that needs the module waits for the lock to time
    /// out. So on Windows the graceful steps (which end with `CTRL_BREAK_EVENT` to the plugin's process group) get long
    /// enough to let those compilers exit on their own before the group is force-terminated.
    static var cancellablePluginRun: Self {
        #if os(Windows)
        return cancellable(gracePeriod: .seconds(5))
        #else
        return cancellable()
        #endif
    }
}
