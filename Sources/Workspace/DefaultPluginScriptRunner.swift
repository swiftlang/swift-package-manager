/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import TSCBasic

import struct TSCUtility.Triple

/// A plugin script runner that compiles the plugin source files as an executable binary for the host platform, and invokes it as a subprocess.
public struct DefaultPluginScriptRunner: PluginScriptRunner {
    let fileSystem: FileSystem
    let cacheDir: AbsolutePath
    let toolchain: ToolchainConfiguration
    let enableSandbox: Bool

    private static var _hostTriple = ThreadSafeBox<Triple>()
    private static var _packageDescriptionMinimumDeploymentTarget = ThreadSafeBox<String>()
    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    public init(fileSystem: FileSystem, cacheDir: AbsolutePath, toolchain: ToolchainConfiguration, enableSandbox: Bool = true) {
        self.fileSystem = fileSystem
        self.cacheDir = cacheDir
        self.toolchain = toolchain
        self.enableSandbox = enableSandbox
    }
    
    /// Public protocol function that starts compiling the plugin script to an exectutable. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not of the target to which it is being applied). This function returns immediately and then calls the completion handler on the callbackq queue when compilation ends.
    public func compilePluginScript(
        sources: Sources,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        self.compile(
            sources: sources,
            toolsVersion: toolsVersion,
            cacheDir: self.cacheDir,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            completion: completion)
    }

    /// A synchronous version of `compilePluginScript()`.
    public func compilePluginScript(
        sources: Sources,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope
    ) throws -> PluginCompilationResult {
        // Call the asynchronous version. In our case we don't care which queue the callback occurs on.
        return try tsc_await { self.compilePluginScript(
            sources: sources,
            toolsVersion: toolsVersion,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue.sharedConcurrent,
            completion: $0)
        }
    }

    /// Public protocol function that starts evaluating a plugin by compiling it and running it as a subprocess. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not the package containing the target to which it is being applied). This function returns immediately and then repeated calls the output handler on the given callback queue as plain-text output is received from the plugin, and then eventually calls the completion handler on the given callback queue once the plugin is done.
    public func runPluginScript(
        sources: Sources,
        initialMessage: Data,
        toolsVersion: ToolsVersion,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptRunnerDelegate,
        completion: @escaping (Result<Int32, Error>) -> Void
    ) {
        // If needed, compile the plugin script to an executable (asynchronously). Compilation is skipped if the plugin hasn't changed since it was last compiled.
        self.compile(
            sources: sources,
            toolsVersion: toolsVersion,
            cacheDir: self.cacheDir,
            fileSystem: self.fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue.sharedConcurrent,
            completion: {
                dispatchPrecondition(condition: .onQueue(DispatchQueue.sharedConcurrent))
                switch $0 {
                case .success(let result):
                    if result.succeeded {
                        // Compilation succeeded, so run the executable. We are already running on an asynchronous queue.
                        self.invoke(
                            compiledExec: result.compiledExecutable,
                            workingDirectory: workingDirectory,
                            writableDirectories: writableDirectories,
                            readOnlyDirectories: readOnlyDirectories,
                            initialMessage: initialMessage,
                            observabilityScope: observabilityScope,
                            callbackQueue: callbackQueue,
                            delegate: delegate,
                            completion: completion)
                    }
                    else {
                        // Compilation failed, so throw an error.
                        callbackQueue.async { completion(.failure(DefaultPluginScriptRunnerError.compilationFailed(result))) }
                    }
                case .failure(let error):
                    // Compilation failed, so just call the callback block on the appropriate queue.
                    callbackQueue.async { completion(.failure(error)) }
                }
            }
        )
    }

    public var hostTriple: Triple {
        return Self._hostTriple.memoize {
            Triple.getHostTriple(usingSwiftCompiler: self.toolchain.swiftCompilerPath)
        }
    }
    
    /// Helper function that starts compiling a plugin script asynchronously and when done, calls the completion handler with the compilation results (including the path of the compiled plugin executable and with any emitted diagnostics, etc). This function only throws an error if it wasn't even possible to start compiling the plugin — any regular compilation errors or warnings will be reflected in the returned compilation result.
    fileprivate func compile(
        sources: Sources,
        toolsVersion: ToolsVersion,
        cacheDir: AbsolutePath,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        // FIXME: Much of this is similar to what the ManifestLoader is doing. This should be consolidated.
        do {
            // We could name the executable anything, but using the plugin name makes it more understandable.
            let execName = sources.root.basename.spm_mangledToC99ExtendedIdentifier()

            // Get access to the path containing the PackagePlugin module and library.
            let runtimePath = self.toolchain.swiftPMLibrariesLocation.pluginAPI

            // We use the toolchain's Swift compiler for compiling the plugin.
            var command = [self.toolchain.swiftCompilerPath.pathString]

            let macOSPackageDescriptionPath: AbsolutePath
            // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
            // which produces a framework for dynamic package products.
            if runtimePath.extension == "framework" {
                command += [
                    "-F", runtimePath.parentDirectory.pathString,
                    "-framework", "PackagePlugin",
                    "-Xlinker", "-rpath", "-Xlinker", runtimePath.parentDirectory.pathString,
                ]
                macOSPackageDescriptionPath = runtimePath.appending(component: "PackagePlugin")
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
                macOSPackageDescriptionPath = runtimePath.appending(component: "libPackagePlugin.dylib")
            }

            #if os(macOS)
            // On macOS earlier than 12, add an rpath to the directory that contains the concurrency fallback library.
            if #available(macOS 12.0, *) {
                // Nothing is needed; the system has everything we need.
            }
            else {
                // Add an `-rpath` so the Swift 5.5 fallback libraries can be found.
                let swiftSupportLibPath = self.toolchain.swiftCompilerPath.parentDirectory.parentDirectory.appending(components: "lib", "swift-5.5", "macosx")
                command += ["-Xlinker", "-rpath", "-Xlinker", swiftSupportLibPath.pathString]
            }
            #endif

            // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
            #if os(macOS)
            let triple = self.hostTriple
            let version = try Self._packageDescriptionMinimumDeploymentTarget.memoize {
                (try Self.computeMinimumDeploymentTarget(of: macOSPackageDescriptionPath))?.versionString ?? "10.15"
            }
            command += ["-target", "\(triple.tripleString(forPlatformVersion: version))"]
            #endif

            // Add any extra flags required as indicated by the ManifestLoader.
            command += self.toolchain.swiftCompilerFlags

            // Add the Swift language version implied by the package tools version.
            command += ["-swift-version", toolsVersion.swiftLanguageVersion.rawValue]

            // Add the PackageDescription version specified by the package tools version, which controls what PackagePlugin API is seen.
            command += ["-package-description-version", toolsVersion.description]

            // if runtimePath is set to "PackageFrameworks" that means we could be developing SwiftPM in Xcode
            // which produces a framework for dynamic package products.
            if runtimePath.extension == "framework" {
                command += ["-I", runtimePath.parentDirectory.parentDirectory.pathString]
            } else {
                command += ["-I", runtimePath.pathString]
            }
            #if os(macOS)
            if let sdkRoot = self.toolchain.sdkRootPath ?? self.sdkRoot() {
                command += ["-sdk", sdkRoot.pathString]
            }
            #endif

            // Honor any module cache override that's set in the environment.
            let moduleCachePath = ProcessEnv.vars["SWIFTPM_MODULECACHE_OVERRIDE"] ?? ProcessEnv.vars["SWIFTPM_TESTS_MODULECACHE"]
            if let moduleCachePath = moduleCachePath {
                command += ["-module-cache-path", moduleCachePath]
            }

            // Parse the plugin as a library so that `@main` is supported even though there might be only a single source file.
            command += ["-parse-as-library"]

            // Add options to create a .dia file containing any diagnostics emitted by the compiler.
            let diagnosticsFile = cacheDir.appending(component: "\(execName).dia")
            command += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticsFile.pathString]

            // Add all the source files that comprise the plugin scripts.
            command += sources.paths.map { $0.pathString }

            // Add the path of the compiled executable.
#if os(Windows)
            let execSuffix = ".exe"
#else
            let execSuffix = ""
#endif
            let executableFile = cacheDir.appending(component: execName + execSuffix)
            command += ["-o", executableFile.pathString]
        
            // Create the cache directory in which we'll be placing the compiled executable if needed.
            try FileManager.default.createDirectory(at: cacheDir.asURL, withIntermediateDirectories: true, attributes: nil)
        
            // Hash the command line and the contents of the source files to decide whether we need to recompile the plugin executable.
            let compilerInputsHash: String?
            do {
                // We include the full command line, the environment, and the contents of the source files.
                let stream = BufferedOutputByteStream()
                stream <<< command
                for (key, value) in toolchain.swiftCompilerEnvironment.sorted(by: { $0.key < $1.key }) {
                    stream <<< "\(key)=\(value)\n"
                }
                for sourceFile in sources.paths {
                    try stream <<< fileSystem.readFileContents(sourceFile).contents
                }
                compilerInputsHash = stream.bytes.sha256Checksum
                observabilityScope.emit(debug: "Computed hash of plugin compilation inputs: \(compilerInputsHash!)")
            }
            catch {
                // We failed to compute the hash. We warn about it but proceed with the compilation (a cache miss).
                observabilityScope.emit(warning: "Couldn't compute hash of plugin compilation inputs (\(error)")
                compilerInputsHash = .none
            }

            // If we already have a compiled executable, then compare its hash with the new one.
            var compilationNeeded = true
            let hashFile = executableFile.parentDirectory.appending(component: execName + ".inputhash")
            if fileSystem.exists(executableFile) && fileSystem.exists(hashFile) {
                do {
                    if (try fileSystem.readFileContents(hashFile)) == compilerInputsHash {
                        compilationNeeded = false
                    }
                }
                catch {
                    // We failed to read the `.inputhash` file. We warn about it but proceed with the compilation (a cache miss).
                    observabilityScope.emit(warning: "Couldn't read previous hash of plugin compilation inputs (\(error)")
                }
            }
            if compilationNeeded {
                // We need to recompile the executable, so we do so asynchronously.
                Process.popen(arguments: command, environment: toolchain.swiftCompilerEnvironment, queue: callbackQueue) {
                    // We are now on our caller's requested callback queue, so we just call the completion handler directly.
                    dispatchPrecondition(condition: .onQueue(callbackQueue))
                    completion($0.tryMap {
                        // Emit the compiler output as observable info.
                        let compilerOutput = ((try? $0.utf8Output()) ?? "") + ((try? $0.utf8stderrOutput()) ?? "")
                        observabilityScope.emit(info: compilerOutput)

                        // We return a PluginCompilationResult for both the successful and unsuccessful cases (to convey diagnostics, etc).
                        let result = PluginCompilationResult(
                            compilerResult: $0,
                            diagnosticsFile: diagnosticsFile,
                            compiledExecutable: executableFile,
                            wasCached: false)
                        guard $0.exitStatus == .terminated(code: 0) else {
                            // Try to clean up any old executable and hash file that might still be around from before.
                            try? fileSystem.removeFileTree(executableFile)
                            try? fileSystem.removeFileTree(hashFile)
                            return result
                        }

                        // We only get here if the compilation succeeded.
                        do {
                            // Write out the hash of the inputs so we can compare the next time we try to compile.
                            if let newHash = compilerInputsHash {
                                try fileSystem.writeFileContents(hashFile, string: newHash)
                            }
                        }
                        catch {
                            // We failed to write the `.inputhash` file. We warn about it but proceed.
                            observabilityScope.emit(warning: "Couldn't write new hash of plugin compilation inputs (\(error)")
                        }
                        return result
                    })
                }
            }
            else {
                // There is no need to recompile the executable, so we just call the completion handler with the results from last time.
                let result = PluginCompilationResult(
                    compilerResult: .none,
                    diagnosticsFile: diagnosticsFile,
                    compiledExecutable: executableFile,
                    wasCached: true)
                callbackQueue.async {
                    completion(.success(result))
                }
            }
        }
        catch {
            // We get here if we didn't even get far enough to invoke the compiler before hitting an error.
            callbackQueue.async { completion(.failure(DefaultPluginScriptRunnerError.compilationPreparationFailed(error: error))) }
        }
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
    
    /// Private function that invokes a compiled plugin executable and communicates with it until it finishes.
    fileprivate func invoke(
        compiledExec: AbsolutePath,
        workingDirectory: AbsolutePath,
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        initialMessage: Data,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginScriptRunnerDelegate,
        completion: @escaping (Result<Int32, Error>) -> Void
    ) {
#if os(iOS) || os(watchOS) || os(tvOS)
        callbackQueue.async {
            completion(.failure(DefaultPluginScriptRunnerError.pluginUnavailable(reason: "subprocess invocations are unavailable on this platform")))
        }
#else
        // Construct the command line. Currently we just invoke the executable built from the plugin without any parameters.
        var command = [compiledExec.pathString]

        // Optionally wrap the command in a sandbox, which places some limits on what it can do. In particular, it blocks network access and restricts the paths to which the plugin can make file system changes. It does allow writing to temporary directories.
        if self.enableSandbox {
            command = Sandbox.apply(command: command, strictness: .writableTemporaryDirectory, writableDirectories: writableDirectories + [self.cacheDir], readOnlyDirectories: readOnlyDirectories)
        }

        // Create and configure a Process. We set the working directory to the cache directory, so that relative paths end up there.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = workingDirectory.asURL
        
        // Set up a pipe for sending structured messages to the plugin on its stdin.
        let stdinPipe = Pipe()
        let outputHandle = stdinPipe.fileHandleForWriting
        let outputQueue = DispatchQueue(label: "plugin-send-queue")
        process.standardInput = stdinPipe

        // Set up a pipe for receiving messages from the plugin on its stdout.
        let stdoutPipe = Pipe()
        let stdoutLock = Lock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            // Receive the next message and pass it on to the delegate.
            stdoutLock.withLock {
                do {
                    while let message = try fileHandle.readPluginMessage() {
                        // FIXME: We should handle errors here.
                        callbackQueue.async {
                            do {
                                try delegate.handleMessage(data: message, responder: { data in
                                    outputQueue.async {
                                        do {
                                            try outputHandle.writePluginMessage(data)
                                        }
                                        catch {
                                            print("error while trying to send message to plugin: \(error)")
                                        }
                                    }
                                })
                            }
                            catch {
                                print("error while trying to handle message from plugin: \(error)")
                            }
                        }
                    }
                }
                catch {
                    print("error while trying to read message from plugin: \(error)")
                }
            }
        }
        process.standardOutput = stdoutPipe

        // Set up a pipe for receiving free-form text output from the plugin on its stderr.
        let stderrPipe = Pipe()
        let stderrLock = Lock()
        var stderrData = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            // Pass on any available data to the delegate.
            stderrLock.withLock {
                let data = fileHandle.availableData
                if data.isEmpty { return }
                stderrData.append(contentsOf: data)
                callbackQueue.async { delegate.handleOutput(data: data) }
            }
        }
        process.standardError = stderrPipe
        
        // Add it to the list of currently running plugin processes, so it can be cancelled if the host is interrupted.
        DefaultPluginScriptRunner.currentlyRunningPlugins.lock.withLock {
            _ = DefaultPluginScriptRunner.currentlyRunningPlugins.processes.insert(process)
        }

        // Set up a handler to deal with the exit of the plugin process.
        process.terminationHandler = { process in
            // Remove the process from the list of currently running ones.
            DefaultPluginScriptRunner.currentlyRunningPlugins.lock.withLock {
                _ = DefaultPluginScriptRunner.currentlyRunningPlugins.processes.remove(process)
            }

            // Close the output handle through which we talked to the plugin.
            try? outputHandle.close()

            // Read and pass on any remaining free-form text output from the plugin.
            stderrPipe.fileHandleForReading.readabilityHandler?(stderrPipe.fileHandleForReading)

            // Read and pass on any remaining messages from the plugin.
            stdoutPipe.fileHandleForReading.readabilityHandler?(stdoutPipe.fileHandleForReading)

            // Call the completion block with a result that depends on how the process ended.
            callbackQueue.async {
                completion(Result {
                    // We throw an error if the plugin ended with a signal.
                    if process.terminationReason == .uncaughtSignal {
                        throw DefaultPluginScriptRunnerError.invocationEndedBySignal(
                            signal: process.terminationStatus,
                            command: command,
                            output: String(decoding: stderrData, as: UTF8.self))
                    }
                    // Otherwise return the termination satatus.
                    return process.terminationStatus
                })
            }
        }
 
        // Start the plugin process.
        do {
            try process.run()
        }
        catch {
            callbackQueue.async {
                completion(.failure(DefaultPluginScriptRunnerError.invocationFailed(error: error, command: command)))
            }
        }

        /// Send the initial message to the plugin.
        outputQueue.async {
            try? outputHandle.writePluginMessage(initialMessage)
        }
#endif
    }
    
    /// Cancels all currently running plugins, resulting in an error code indicating that they were interrupted. This is intended for use when the host process is interrupted.
    public static func cancelAllRunningPlugins() {
#if !os(iOS) && !os(watchOS) && !os(tvOS)
        currentlyRunningPlugins.lock.withLock {
            currentlyRunningPlugins.processes.forEach{
                $0.terminate()
            }
            currentlyRunningPlugins.processes = []
        }
#endif
    }
    /// Private list of currently running plugin processes and the lock that protects the list.
#if !os(iOS) && !os(watchOS) && !os(tvOS)
    private static var currentlyRunningPlugins: (processes: Set<Foundation.Process>, lock: Lock) = (.init(), .init())
#endif
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
            return "plugin compilation preparation failed: \(error)"
        case .compilationFailed(let result):
            return "plugin compilation failed: \(result)"
        case .invocationFailed(let error, let command):
            return "plugin invocation failed: \(error) \(makeContextString(command, ""))"
        case .invocationEndedBySignal(let signal, let command, let output):
            return "plugin process ended by an uncaught signal: \(signal) \(makeContextString(command, output))"
        case .invocationEndedWithNonZeroExitCode(let exitCode, let command, let output):
            return "plugin process ended with a non-zero exit code: \(exitCode) \(makeContextString(command, output))"
        case .pluginCommunicationError(let message, let command, let output):
            return "plugin communication error: \(message) \(makeContextString(command, output))"
        }
    }
}

fileprivate extension FileHandle {
    
    func writePluginMessage(_ message: Data) throws {
        // Write the header (a 64-bit length field in little endian byte order).
        var length = UInt64(littleEndian: UInt64(message.count))
        let header = Swift.withUnsafeBytes(of: &length) { Data($0) }
        assert(header.count == 8)
        try self.write(contentsOf: header)
        
        // Write the payload.
        try self.write(contentsOf: message)
    }
    
    func readPluginMessage() throws -> Data? {
        // Read the header (a 64-bit length field in little endian byte order).
        guard let header = try self.read(upToCount: 8) else { return nil }
        guard header.count == 8 else {
            throw PluginMessageError.truncatedHeader
        }
        let length = header.withUnsafeBytes{ $0.load(as: UInt64.self).littleEndian }
        guard length >= 2 else {
            throw PluginMessageError.invalidPayloadSize
        }

        // Read and return the message.
        guard let message = try self.read(upToCount: Int(length)), message.count == length else {
            throw PluginMessageError.truncatedPayload
        }
        return message
    }

    enum PluginMessageError: Swift.Error {
        case truncatedHeader
        case invalidPayloadSize
        case truncatedPayload
    }
}
