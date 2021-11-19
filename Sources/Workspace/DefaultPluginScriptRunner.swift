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
    
    public func compilePluginScript(
        sources: Sources,
        toolsVersion: ToolsVersion,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        self.compile(sources: sources, toolsVersion: toolsVersion, cacheDir: self.cacheDir, observabilityScope: observabilityScope, on: queue, completion: completion)
    }

    /// Public protocol function that starting evaluating a plugin by compiling it and running it as a subprocess. The tools version controls the availability of APIs in PackagePlugin, and should be set to the tools version of the package that defines the plugin (not of the target to which it is being applied). This function returns immediately and then calls the output handler as plain-text output is received from the plugin, and calls the completion handler once it finishes running.
    public func runPluginScript(
        sources: Sources,
        input: PluginScriptRunnerInput,
        toolsVersion: ToolsVersion,
        writableDirectories: [AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        on queue: DispatchQueue,
        outputHandler: @escaping (Data) -> Void,
        completion: @escaping (Result<PluginScriptRunnerOutput, Error>) -> Void
    ) {
        // TODO: Skip compiling the plugin script if it has already been compiled and hasn't changed.
        self.compile(sources: sources, toolsVersion: toolsVersion, cacheDir: self.cacheDir, observabilityScope: observabilityScope, on: queue) { result in
            switch result {
            case .success(let result):
                guard let compiledExecutable = result.compiledExecutable else {
                    return completion(.failure(DefaultPluginScriptRunnerError.compilationFailed(result)))
                }
                self.invoke(
                    compiledExec: compiledExecutable,
                    writableDirectories: writableDirectories,
                    input: input,
                    observabilityScope: observabilityScope,
                    on: queue,
                    outputHandler: outputHandler,
                    completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
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
        on queue: DispatchQueue,
        completion: @escaping (Result<PluginCompilationResult, Error>) -> Void
    ) {
        // FIXME: Much of this is copied from the ManifestLoader and should be consolidated.

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
        
        // Create the cache directory in which we'll be placing the compiled executable if needed. Any failure to create it will be reported by the compiler.
        try? FileManager.default.createDirectory(at: cacheDir.asURL, withIntermediateDirectories: true, attributes: nil)
        
        Process.popen(arguments: command, environment: toolchain.swiftCompilerEnvironment, queue: queue) { result in
            switch result {
            case .success(let processResult):
                // We return the path of the compiled executable only if the compilation succeeded.
                let compiledExecutable = (processResult.exitStatus == .terminated(code: 0)) ? executableFile : nil
                let compilationResult = PluginCompilationResult(compiledExecutable: compiledExecutable, diagnosticsFile: diagnosticsFile, compilerResult: processResult)
                completion(.success(compilationResult))
            case .failure(let error):
                completion(.failure(error))
            }
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
        on queue: DispatchQueue,
        outputHandler: @escaping (Data) -> Void,
        completion: @escaping (Result<PluginScriptRunnerOutput, Error>) -> Void
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
        
        // Create a dispatch group for waiting on proces termination and all output from it.
        let waiters = DispatchGroup()
        
        // Set up a pipe for receiving free-form text output from the plugin on its stderr.
        waiters.enter()
        let stderrPipe = Pipe()
        var stderrData = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { (fileHandle: FileHandle) -> Void in
            // We just pass the data on to our given output handler.
            let newData = fileHandle.availableData
            if newData.isEmpty {
                fileHandle.readabilityHandler = nil
                waiters.leave()
            }
            else {
                stderrData.append(contentsOf: newData)
                queue.async { outputHandler(newData) }
            }
        }
        process.standardError = stderrPipe

        // Set up a pipe for receiving structured messages from the plugin on its stdout.
        let stdoutPipe = Pipe()
        let inputHandle = stdoutPipe.fileHandleForReading
        process.standardOutput = stdoutPipe
        
        // Set up a pipe for sending structured messages to the plugin on its stdin.
        let stdinPipe = Pipe()
        let outputHandle = stdinPipe.fileHandleForWriting
        process.standardInput = stdinPipe

        // Set up a termination handler.
        process.terminationHandler = { _ in
            // We don't do anything special other than note the process exit.
            waiters.leave()
        }

        waiters.enter()
        do {
            // Start the plugin process.
            try process.run()
            
            /// Send an initial message to the plugin to ask it to perform its action based on the input data.
            try outputHandle.writePluginMessage(.performAction(input: input))
            
            /// Get messages from the plugin. It might tell us it's done or ask us for more information.
            var result: PluginScriptRunnerOutput? = nil
            while let message = try inputHandle.readPluginMessage() {
                switch message {
                case .provideResult(let output):
                    result = output
                    try outputHandle.writePluginMessage(.quit)
                }
            }
            
            // Wait for the process to terminate and the readers to finish collecting all output.
            waiters.wait()

            switch process.terminationReason {
            case .uncaughtSignal:
                throw StringError("plugin process ended by an uncaught signal")
            case .exit:
                if process.terminationStatus != 0 {
                    throw StringError("plugin process ended with a non-zero exit code: \(process.terminationStatus)")
                }
            default:
                throw StringError("plugin process ended for unexpected reason")
            }
            guard let result = result else {
                throw StringError("didn’t receive output from plugin")
            }
            queue.async { completion(.success(result)) }
        }
        catch {
            queue.async { completion(.failure(DefaultPluginScriptRunnerError.invocationFailed(error, command: command))) }
        }
    }
}

/// The result of compiling a plugin. The executable path will only be present if the compilation succeeds, while the other properties are present in all cases.
public struct PluginCompilationResult {
    /// Path of the compiled executable, or .none if compilation failed.
    public var compiledExecutable: AbsolutePath?
    
    /// Path of the libClang diagnostics file emitted by the compiler (even if compilation succeded, it might contain warnings).
    public  var diagnosticsFile: AbsolutePath
    
    /// Process result of invoking the Swift compiler to produce the executable (contains command line, environment, exit status, and any output).
    public var compilerResult: ProcessResult
}


/// An error encountered by the default plugin runner.
public enum DefaultPluginScriptRunnerError: Error {
    case compilationFailed(PluginCompilationResult)
    case invocationFailed(_ error: Error, command: [String])
}

extension DefaultPluginScriptRunnerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .compilationFailed(let result):
            return "plugin script compilation failed: \(result)"
        case .invocationFailed(let message, _):
            return "plugin invocation failed: \(message)"
        }
    }
}

/// A message that the host can send to the plugin.
enum HostToPluginMessage: Codable {
    case performAction(input: PluginScriptRunnerInput)
    case quit
}

/// A message that the plugin can send to the host.
enum PluginToHostMessage: Codable {
    case provideResult(output: PluginScriptRunnerOutput)
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
