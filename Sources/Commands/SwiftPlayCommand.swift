//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore

import enum TSCUtility.Diagnostics

#if canImport(Android)
import Android
#endif

struct PlayCommandOptions: ParsableArguments {
    enum PlayMode: EnumerableFlag {
        /// Build and execute playground and then automatically re-build and re-execute on any file changes
        case liveUpdate
        
        /// Build and execute playground one time and immediately exit
        case oneShot

        static func help(for value: PlayCommandOptions.PlayMode) -> ArgumentHelp? {
            switch value {
            case .oneShot:
                return "Execute playground and exit immediately"
            case .liveUpdate:
                return "Execute playground and automatically re-execute on any source file changes"
            }
        }
    }

    /// The mode in with the tool command should run.
    @Flag var mode: PlayMode = .liveUpdate

    /// The playground to run.
    @Argument(help: "The playground name to run", completion: .shellCommand("swift package completion-tool list-playgrounds"))
    var playgroundName: String = ""

    /// Specifies the traits to build the product with.
    @OptionGroup(visibility: .hidden)
    package var traits: TraitOptions

    /// List found playgrounds instead of running them
    @Flag(name: .customLong("list"), help: "List all Playgrounds")
    var list: Bool = false
}

/// swift-play command namespace
public struct SwiftPlayCommand: AsyncSwiftCommand {
    public static var configuration = CommandConfiguration(
        commandName: "play",
        _superCommandName: "swift",
        abstract: "Build and run a playground",
        discussion: "SEE ALSO: swift build, swift package, swift run, swift test",
        version: SwiftVersion.current.completeDisplayString,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    public var globalOptions: GlobalOptions

    @OptionGroup()
    var options: PlayCommandOptions

    public var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        // Enabling the Playground product ensures a playground runner executable
        // is synthesized for `swift play` to access and run playground macro code.
        return .init(wantsPlaygroundProduct: true)
    }

    public func run(_ swiftCommandState: SwiftCommandState) async throws {
        if options.playgroundName == "" && !options.list {
            throw ValidationError("Missing Playground name")
        }
        
        var productsBuildParameters = try swiftCommandState.productsBuildParameters

        // Append additional build flags from the environment
        if let envSwiftcOptions = ProcessInfo.processInfo.environment["SWIFTC_FLAGS"] {
            var flags = productsBuildParameters.flags
            let additionalFlags = envSwiftcOptions.components(separatedBy: CharacterSet.whitespaces)
            flags.swiftCompilerFlags += additionalFlags
            productsBuildParameters.flags = flags
        }

        var buildAndPlayAgain: Bool = false

        repeat {
            do {
                let buildResult = try await buildPlaygroundRunner(
                    swiftCommandState: swiftCommandState,
                    productsBuildParameters: productsBuildParameters
                )

                if case .failure(_) = buildResult {
                    print("Build failed")

                    if !buildAndPlayAgain {
                        // Exit immediately when initial build fails
                        break
                    }
                }

                let result = try await startPlaygroundAndMonitorFilesIfNeeded(
                    buildResult: buildResult,
                    swiftCommandState: swiftCommandState
                )

                buildAndPlayAgain = (result == .shouldPlayAgain)

            } catch Diagnostics.fatalError {
                throw ExitCode.failure
            }
        } while (buildAndPlayAgain)
    }

    /// Builds the playground runner executable product.
    ///
    /// This method creates a build system using the provided Swift command state and build parameters,
    /// then locates and builds the playground runner executable product that will be used to execute
    /// playground code.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The Swift command state containing workspace and configuration information
    ///   - productsBuildParameters: Build parameters specifying compilation settings and output paths
    ///
    /// - Returns: A `Result` containing either the name of the successfully built playground runner
    ///            product on success, or an `Error` on failure
    ///
    /// - Throws: `ExitCode.failure` if no playground runner executable product can be found in the
    ///           package graph
    private func buildPlaygroundRunner(
        swiftCommandState: SwiftCommandState,
        productsBuildParameters: BuildParameters
    ) async throws -> Result<String, Error> {
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitProduct: nil,
            traitConfiguration: .init(traitOptions: self.options.traits),
            productsBuildParameters: productsBuildParameters
        )

        let allProducts = try await buildSystem.getPackageGraph().reachableProducts
        if globalOptions.logging.veryVerbose {
            for product in allProducts {
                verboseLog("Found product: \(product)")
            }
            verboseLog("- Found \(allProducts.count) product\(allProducts.count==1 ? "" : "s")")
        }

        guard let playgroundExecutableProduct = allProducts.first(where: { $0.underlying.isPlaygroundRunner }) else {
            print("Could not create a playground executable.")
            throw ExitCode.failure
        }
        verboseLog("Choosing product \"\(playgroundExecutableProduct.name)\", type: \(playgroundExecutableProduct.type)")

        // Build the playground runner executable product
        do {
            try await buildSystem.build(subset: .product(playgroundExecutableProduct.name))
            return Result.success(playgroundExecutableProduct.name)
        } catch {
            return Result.failure(error)
        }
    }

    private enum PlaygroundMonitorResult {
        /// Indicates that the playground should be rebuilt and executed again
        case shouldPlayAgain
        /// Indicates that all playground monitoring and execution has finished
        case shouldExit
    }

    /// Starts the playground runner process and monitors for file changes if in live update mode.
    ///
    /// This method handles the execution of the playground runner executable and optionally monitors
    /// source files for changes to enable automatic re-building and re-execution. The behavior
    /// depends on the configured play mode:
    /// - In `.oneShot` mode: Executes the playground once and exits immediately
    /// - In `.liveUpdate` mode: Executes the playground and monitors for file changes to trigger rebuilds
    ///
    /// - Parameters:
    ///   - buildResult: The result of building the playground runner executable, containing either
    ///                  the product name on success or an error on failure
    ///   - swiftCommandState: The Swift command state containing workspace configuration and file system access
    ///
    /// - Returns: A `PlaygroundMonitorResult` indicating the next action:
    ///   - `.shouldPlayAgain`: File changes were detected in live update mode, requiring a rebuild
    ///   - `.shouldExit`: The process completed normally or is running in one-shot mode
    ///
    /// - Throws: `ExitCode.failure` if the current working directory cannot be determined or if file
    ///           monitoring setup fails on macOS platforms
    ///
    /// - Note: File monitoring is only currently available on macOS. On other platforms, live update mode will
    ///         behave similarly to one-shot mode after the initial execution.
    private func startPlaygroundAndMonitorFilesIfNeeded(
        buildResult: Result<String, Error>,
        swiftCommandState: SwiftCommandState
    ) async throws -> PlaygroundMonitorResult {

        // Hand off playground execution to dynamically built playground runner executable
        var runnerProcess: AsyncProcess? = nil
        defer {
            runnerProcess?.signal(SIGKILL)
        }

        if case let .success(productName) = buildResult {
            // Build was successful so launch the playground runner executable that was just built
            let productRelativePath = try swiftCommandState.productsBuildParameters.executablePath(for: productName)
            let runnerExecutablePath = try swiftCommandState.productsBuildParameters.buildPath.appending(productRelativePath)

            runnerProcess = try self.play(
                executablePath: runnerExecutablePath,
                originalWorkingDirectory: swiftCommandState.originalWorkingDirectory
            )
        }

        if options.mode == .oneShot || options.list {
            // Call playground runner (if available) then immediately exit
            try await runnerProcess?.waitUntilExit()
            return .shouldExit // don't build & play again
        }
        else {
            // Live update mode: re-build/re-run on file changes

            guard let monitorURL = swiftCommandState.fileSystem.currentWorkingDirectory?.asURL else {
                print("[No cwd]")
                throw ExitCode.failure
            }

#if os(macOS)
            // Monitor for file changes
            let fileMonitor: FileMonitor
            do {
                verboseLog("Monitoring files at \(monitorURL)")
                fileMonitor = try FileMonitor(
                    url: monitorURL,
                    verboseLogging: globalOptions.logging.veryVerbose
                )
            } catch {
                print("FileMonitor failed for \(monitorURL): \(error)")
                throw ExitCode.failure
            }

            defer {
                fileMonitor.cancel()
            }
#endif

            verboseLog("swift play waiting...")

            enum ProcessAndFileMonitorResult {
                /// A source file was changed
                case fileChanged
                /// The monitored process exited
                case processExited
            }

            // Wait for either the process to finish or file changes to occur
            let result = await withTaskGroup(of: ProcessAndFileMonitorResult.self) { group in

                // Task to wait for process completion, if a process is running.
                // A process won't be running if the build fails, for example, but
                // we still want to watch for file changes below to re-build/re-run.
                if let runnerProcess {
                    group.addTask {
                        do {
                            try await runnerProcess.waitUntilExit()
                        } catch {
                            verboseLog("Runner process exited with error: \(error)")
                        }
                        return .processExited
                    }
                }

#if os(macOS)
                // Task to wait for file changes
                group.addTask {
                    await fileMonitor.waitForChanges()
                    return .fileChanged
                }
#endif

                // Return the first result from either task
                let firstResult = await group.next()

                // Cancel remaining tasks
                group.cancelAll()

                // Kill runner process, so that its task ends
                runnerProcess?.signal(SIGKILL)

                guard let result = firstResult else {
                    // taskGroup returned no value so default to processExited
                    return ProcessAndFileMonitorResult.processExited
                }

                return result
            }

            switch result {
            case .fileChanged:
                verboseLog("Files changed, restarting...")
                return .shouldPlayAgain
            case .processExited:
                verboseLog("Process exited")
                return .shouldExit
            }
        }
    }

    /// Executes the Playground via the specified executable at the specified path.
    private func play(
        executablePath: Basics.AbsolutePath,
        originalWorkingDirectory: Basics.AbsolutePath
    ) throws -> AsyncProcess {
        var runnerArguments: [String] = []
        if options.mode == .oneShot {
            runnerArguments.append("--one-shot")
        }
        runnerArguments.append(options.list ? "--list" : options.playgroundName)

        let runnerProcess = AsyncProcess(
            arguments: [executablePath.pathString] + runnerArguments,
            workingDirectory: originalWorkingDirectory,
            inputRedirection: .none,    // route parent process' stdin to playground runner process
            outputRedirection: .none,   // route playground runner process' stdout/stderr to default output
            startNewProcessGroup: false // runner process tracks the parent process' lifetime
        )

        do {
            verboseLog("Launching runner: \(executablePath.pathString) \(runnerArguments.joined(separator: " "))")
            try runnerProcess.launch()
            verboseLog("Runner launched with pid \(runnerProcess.processID)")
        } catch {
            print("[Playground runner launch failed with error: \(error)]")
            throw ExitCode.failure
        }
        
        return runnerProcess
    }

    private func verboseLog(_ message: String) {
        if globalOptions.logging.veryVerbose {
            print("[swift play: \(message)]")
        }
    }

    public init() {}
}

#if os(macOS)
final private class FileMonitor {
    
    let url: URL
    var fileHandles: [FileHandle] = []
    var sources: [DispatchSourceFileSystemObject] = []
    
    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation
    var verboseLogging: Bool

    init(url: URL, verboseLogging: Bool = false) throws {
        self.url = url
        self.verboseLogging = verboseLogging

        // Create an async stream for file change notifications
        (self.changeStream, self.changeContinuation) = AsyncStream<Void>.makeStream()
        
        try initializeMonitoring(for: url)
    }
    
    private func initializeMonitoring(for url: URL) throws {
        let directoryContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let subdirs = directoryContents
            .filter { $0.lastPathComponent.hasPrefix(".") == false }
            .filter { url in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    return isDir.boolValue
                }
                return false
            }
        
        for subdirURL in subdirs {
            try monitor(url: subdirURL)
            try initializeMonitoring(for: subdirURL)
        }
    }

    private func monitor(url: URL) throws {
        let monitoredFolderFileDescriptor = open(url.relativePath, O_EVTONLY)
        let fileHandle = FileHandle(fileDescriptor: monitoredFolderFileDescriptor, closeOnDealloc: true)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileHandle.fileDescriptor,
            eventMask: [.all],
            queue: DispatchQueue.global(qos: .background)
        )
        
        source.setEventHandler {
            let event = source.data
            self.process(event: event)
        }
        
        source.setCancelHandler {
            try? fileHandle.close()
        }
        
        source.activate()
        
        sources.append(source)
        fileHandles.append(fileHandle)

        if verboseLogging { print("[Monitoring files at \(url.path())]") }
    }

    func cancel() {
        changeContinuation.finish()
        for source in sources {
            if !source.isCancelled {
                source.cancel()
            }
        }
        self.fileHandles = []
    }
    
    deinit {
        cancel()
    }
    
    private func process(event: DispatchSource.FileSystemEvent) {
        if verboseLogging { print("[FileMonitor event \(event) for \(url.path())]") }
        changeContinuation.yield()
    }

    /// Asynchronously wait for file changes
    func waitForChanges() async {
        if verboseLogging { print("[FileMonitor.waitForChanges() starting]") }
        for await _ in changeStream {
            if verboseLogging { print("[FileMonitor detected change]") }
            // Return immediately when a change is detected
            return
        }
        // If the stream ends without yielding any values, we should still return
        // This can happen if the monitor is cancelled before any changes occur
        if verboseLogging { print("[FileMonitor stream ended without changes]") }
    }
}
#endif
