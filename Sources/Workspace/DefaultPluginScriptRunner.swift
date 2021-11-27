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
import PackageModel
import SPMBuildCore
import TSCBasic
import TSCUtility

/// A plugin script runner that compiles the plugin source files as an executable binary for the host platform, and invokes it as a subprocess.
public struct DefaultPluginScriptRunner: PluginScriptRunner {
    let cacheDir: AbsolutePath
    let toolchain: ToolchainConfiguration
    let enableSandbox: Bool

    private static var _hostTriple = ThreadSafeBox<Triple>()
    private static var _packageDescriptionMinimumDeploymentTarget = ThreadSafeBox<String>()
    private let sdkRootCache = ThreadSafeBox<AbsolutePath>()

    public init(cacheDir: AbsolutePath, toolchain: ToolchainConfiguration, enableSandbox: Bool = true) {
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
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            completion: completion)
    }

    /// Public protocol function that starts evaluating a plugin by compiling it and running it as a subprocess. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not the package containing the target to which it is being applied). This function returns immediately and then repeated calls the output handler on the given callback queue as plain-text output is received from the plugin, and then eventually calls the completion handler on the given callback queue once the plugin is done.
    public func runPluginScript(
        sources: Sources,
        input: PluginScriptRunnerInput,
        toolsVersion: ToolsVersion,
        writableDirectories: [AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginInvocationDelegate,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        // If needed, compile the plugin script to an executable (asynchronously).
        // TODO: Skip compiling the plugin script if it has already been compiled and hasn't changed.
        self.compile(
            sources: sources,
            toolsVersion: toolsVersion,
            cacheDir: self.cacheDir,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue.sharedConcurrent,
            completion: {
                dispatchPrecondition(condition: .onQueue(DispatchQueue.sharedConcurrent))
                switch $0 {
                case .success(let result):
                    // Compilation succeeded, so run the executable. We are already running on an asynchronous queue.
                    self.invoke(
                        compiledExec: result.compiledExecutable,
                        writableDirectories: writableDirectories,
                        input: input,
                        observabilityScope: observabilityScope,
                        callbackQueue: callbackQueue,
                        delegate: delegate,
                        completion: completion)
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
    
    /// Helper function that starts compiling a plugin script as an executable and when done, calls the completion handler with the path of the executable and with any emitted diagnostics, etc. This function only returns an error if it wasn't even possible to start compiling the plugin — any regular compilation errors or warnings will be reflected in the returned compilation result.
    fileprivate func compile(
        sources: Sources,
        toolsVersion: ToolsVersion,
        cacheDir: AbsolutePath,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        // FIXME: Much of this is similar to what the ManifestLoader is doing. This should be consolidated.

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

        // Use the same minimum deployment target as the PackageDescription library (with a fallback of 10.15).
        #if os(macOS)
        let triple = self.hostTriple
        let version = Self._packageDescriptionMinimumDeploymentTarget.memoize {
            (try? Self.computeMinimumDeploymentTarget(of: macOSPackageDescriptionPath))?.versionString ?? "10.15"
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
        let diagnosticsFile = cacheDir.appending(component: "diagnostics.dia")
        command += ["-Xfrontend", "-serialize-diagnostics-path", "-Xfrontend", diagnosticsFile.pathString]
        
        // Add all the source files that comprise the plugin scripts.
        command += sources.paths.map { $0.pathString }
        
        // Add the path of the compiled executable.
        let executableFile = cacheDir.appending(component: "compiled-plugin")
        command += ["-o", executableFile.pathString]
        
        do {
            // Create the cache directory in which we'll be placing the compiled executable if needed.
            try FileManager.default.createDirectory(at: cacheDir.asURL, withIntermediateDirectories: true, attributes: nil)
        
            // Compile the plugin script asynchronously.
            Process.popen(arguments: command, environment: toolchain.swiftCompilerEnvironment, queue: callbackQueue) {
                // We are now on our caller's requested callback queue, so we just call the completion handler directly.
                dispatchPrecondition(condition: .onQueue(callbackQueue))
                completion($0.tryMap {
                    let result = PluginCompilationResult(compilerResult: $0, diagnosticsFile: diagnosticsFile, compiledExecutable: executableFile)
                    guard $0.exitStatus == .terminated(code: 0) else {
                        throw DefaultPluginScriptRunnerError.compilationFailed(result)
                    }
                    return result
                })
            }
        }
        catch {
            // We get here if we didn't even get far enough to invoke the compiler before hitting an error.
            callbackQueue.async { completion(.failure(DefaultPluginScriptRunnerError.compilationSetupFailed(error: error))) }
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
        writableDirectories: [AbsolutePath],
        input: PluginScriptRunnerInput,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        delegate: PluginInvocationDelegate,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        // Construct the command line. Currently we just invoke the executable built from the plugin without any parameters.
        var command = [compiledExec.pathString]

        // Optionally wrap the command in a sandbox, which places some limits on what it can do. In particular, it blocks network access and restricts the paths to which the plugin can make file system changes.
        if self.enableSandbox {
            command = Sandbox.apply(command: command, writableDirectories: writableDirectories + [self.cacheDir])
        }

        // Create and configure a Process. We set the working directory to the cache directory, so that relative paths end up there.
        let process = Process()
        process.executableURL = Foundation.URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.environment = ProcessInfo.processInfo.environment
        process.currentDirectoryURL = self.cacheDir.asURL
        
        // Set up a pipe for sending structured messages to the plugin on its stdin.
        let stdinPipe = Pipe()
        let outputHandle = stdinPipe.fileHandleForWriting
        let outputQueue = DispatchQueue(label: "plugin-send-queue")
        process.standardInput = stdinPipe

        // Private message handler method. Always invoked on the callback queue.
        var result: Bool? = .none
        func handle(message: PluginToHostMessage) throws {
            dispatchPrecondition(condition: .onQueue(callbackQueue))
            switch message {
                
            case .emitDiagnostic(let severity, let message, let file, let line):
                let metadata: ObservabilityMetadata? = file.map {
                    var metadata = ObservabilityMetadata()
                    // FIXME: We should probably report some kind of protocol error if the path isn't valid.
                    metadata.fileLocation = try? .init(.init(validating: $0), line: line)
                    return metadata
                }
                let diagnostic: Basics.Diagnostic
                switch severity {
                case .error:
                    diagnostic = .error(message, metadata: metadata)
                case .warning:
                    diagnostic = .warning(message, metadata: metadata)
                case .remark:
                    diagnostic = .info(message, metadata: metadata)
                }
                delegate.pluginEmittedDiagnostic(diagnostic)
                
            case .defineBuildCommand(let config, let inputFiles, let outputFiles):
                delegate.pluginDefinedBuildCommand(
                    displayName: config.displayName,
                    executable: try AbsolutePath(validating: config.executable),
                    arguments: config.arguments,
                    environment: config.environment,
                    workingDirectory: try config.workingDirectory.map{ try AbsolutePath(validating: $0) },
                    inputFiles: try inputFiles.map{ try AbsolutePath(validating: $0) },
                    outputFiles: try outputFiles.map{ try AbsolutePath(validating: $0) })
                
            case .definePrebuildCommand(let config, let outputFilesDir):
                delegate.pluginDefinedPrebuildCommand(
                    displayName: config.displayName,
                    executable: try AbsolutePath(validating: config.executable),
                    arguments: config.arguments,
                    environment: config.environment,
                    workingDirectory: try config.workingDirectory.map{ try AbsolutePath(validating: $0) },
                    outputFilesDirectory: try AbsolutePath(validating: outputFilesDir))

            case .symbolGraphRequest(let targetName, let options):
                // The plugin requested symbol graph information for a target. We ask the delegate and then send a response.
                delegate.pluginRequestedSymbolGraph(forTarget: targetName, options: options, completion: {
                    switch $0 {
                    case .success(let info):
                        outputQueue.async { try? outputHandle.writePluginMessage(.symbolGraphResponse(info: info)) }
                    case .failure(let error):
                        outputQueue.async { try? outputHandle.writePluginMessage(.errorResponse(error: String(describing: error))) }
                    }
                })

            case .actionComplete(let success):
                // The plugin has indicated that it's finished the requested action.
                result = success
                outputQueue.async {
                    try? outputHandle.close()
                }
            }
        }

        // Set up a pipe for receiving structured messages from the plugin on its stdout.
        let stdoutPipe = Pipe()
        let stdoutLock = Lock()
        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            // Parse the next message and pass it on to the delegate.
            stdoutLock.withLock {
                if let message = try? fileHandle.readPluginMessage() {
                    // FIXME: We should handle errors here.
                    callbackQueue.async { try? handle(message: message) }
                }
            }
        }
        process.standardOutput = stdoutPipe

        // Set up a pipe for receiving free-form text output from the plugin on its stderr.
        let stderrPipe = Pipe()
        let stderrLock = Lock()
        stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            // Pass on any available data to the delegate.
            stderrLock.withLock {
                let newData = fileHandle.availableData
                if newData.isEmpty { return }
                //print("[output] \(String(decoding: newData, as: UTF8.self))")
                callbackQueue.async { delegate.pluginEmittedOutput(newData) }
            }
        }
        process.standardError = stderrPipe
        
        // Set up a handler to deal with the exit of the plugin process.
        process.terminationHandler = { process in
            // Read and pass on any remaining free-form text output from the plugin.
            stderrPipe.fileHandleForReading.readabilityHandler?(stderrPipe.fileHandleForReading)
            
            // Call the completion block with a result that depends on how the process ended.
            callbackQueue.async {
                completion(Result {
                    if process.terminationReason == .uncaughtSignal {
                        throw StringError("plugin process ended by an uncaught signal")
                    }
                    if process.terminationStatus != 0 {
                        throw StringError("plugin process ended with a non-zero exit code: \(process.terminationStatus)")
                    }
                    guard let result = result else {
                        throw StringError("didn’t receive output result from plugin")
                    }
                    return result
                })
            }
        }
 
        // Start the plugin process.
        do {
            try process.run()
        }
        catch {
            callbackQueue.async {
                completion(.failure(DefaultPluginScriptRunnerError.invocationFailed(error, command: command)))
            }
        }

        /// Send an initial message to the plugin to ask it to perform its action based on the input data.
        outputQueue.async {
            try? outputHandle.writePluginMessage(.performAction(input: input))
        }
    }
}

/// The result of compiling a plugin. The executable path will only be present if the compilation succeeds, while the other properties are present in all cases.
public struct PluginCompilationResult {
    /// Process result of invoking the Swift compiler to produce the executable (contains command line, environment, exit status, and any output).
    public var compilerResult: ProcessResult
    
    /// Path of the libClang diagnostics file emitted by the compiler (even if compilation succeded, it might contain warnings).
    public var diagnosticsFile: AbsolutePath
    
    /// Path of the compiled executable.
    public var compiledExecutable: AbsolutePath
}


/// An error encountered by the default plugin runner.
public enum DefaultPluginScriptRunnerError: Error {
    case compilationSetupFailed(error: Error)
    case compilationFailed(PluginCompilationResult)
    case invocationFailed(_ error: Error, command: [String])
}

extension DefaultPluginScriptRunnerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .compilationSetupFailed(let error):
            return "plugin script compilation failed: \(error)"
        case .compilationFailed(let result):
            return "plugin script compilation failed: \(result)"
        case .invocationFailed(let message, _):
            return "plugin invocation failed: \(message)"
        }
    }
}

/// A message that the host can send to the plugin.
enum HostToPluginMessage: Encodable {
    /// The host is requesting that the plugin perform one of its declared plugin actions.
    case performAction(input: PluginScriptRunnerInput)
    
    /// A response to a request for symbol graph information for a target.
    case symbolGraphResponse(info: PluginInvocationSymbolGraphResult)
    
    /// A response of an error while trying to complete a request.
    case errorResponse(error: String)
}

/// A message that the plugin can send to the host.
enum PluginToHostMessage: Decodable {
    /// The plugin emits a diagnostic.
    case emitDiagnostic(severity: DiagnosticSeverity, message: String, file: String?, line: Int?)

    enum DiagnosticSeverity: String, Decodable {
        case error, warning, remark
    }
    
    /// The plugin defines a build command.
    case defineBuildCommand(configuration: CommandConfiguration, inputFiles: [String], outputFiles: [String])

    /// The plugin defines a prebuild command.
    case definePrebuildCommand(configuration: CommandConfiguration, outputFilesDirectory: String)
    
    struct CommandConfiguration: Decodable {
        var displayName: String?
        var executable: String
        var arguments: [String]
        var environment: [String: String]
        var workingDirectory: String?
    }

    /// The plugin is requesting symbol graph information for a given target and set of options.
    case symbolGraphRequest(targetName: String, options: PluginInvocationSymbolGraphOptions)
    
    /// The plugin has finished the requested action.
    case actionComplete(success: Bool)
}

fileprivate extension FileHandle {
    
    func writePluginMessage(_ message: HostToPluginMessage) throws {
        // Encode the message as JSON.
        let payload = try JSONEncoder().encode(message)
        
        // Write the header (a 64-bit length field in little endian byte order).
        var count = UInt64(littleEndian: UInt64(payload.count))
        let header = Swift.withUnsafeBytes(of: &count) { Data($0) }
        assert(header.count == 8)
        try self.write(contentsOf: header)
        
        // Write the payload.
        try self.write(contentsOf: payload)
    }
    
    func readPluginMessage() throws -> PluginToHostMessage? {
        // Read the header (a 64-bit length field in little endian byte order).
        guard let header = try self.read(upToCount: 8) else { return nil }
        guard header.count == 8 else {
            throw PluginMessageError.truncatedHeader
        }
        
        // Decode the count.
        let count = header.withUnsafeBytes{ $0.load(as: UInt64.self).littleEndian }
        guard count >= 2 else {
            throw PluginMessageError.invalidPayloadSize
        }

        // Read the JSON payload.
        guard let payload = try self.read(upToCount: Int(count)), payload.count == count else {
            throw PluginMessageError.truncatedPayload
        }

        // Decode and return the message.
        return try JSONDecoder().decode(PluginToHostMessage.self, from: payload)
    }

    enum PluginMessageError: Swift.Error {
        case truncatedHeader
        case invalidPayloadSize
        case truncatedPayload
    }
}
