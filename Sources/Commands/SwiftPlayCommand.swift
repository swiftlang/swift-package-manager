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

import enum TSCBasic.ProcessEnv
import func TSCBasic.exec
import class TSCBasic.ThreadSafeOutputByteStream
import class TSCBasic.LocalFileOutputByteStream
import var TSCBasic.stdoutStream

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

    private enum ProcessMonitorResult {
        /// A source file was changed
        case fileChanged
        /// The monitored process exited
        case processExited
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

        var playAgain: Bool = false

        repeat {
            do {
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

                // Build the package
                var buildSucceeded = false
                do {
                    try await buildSystem.build(subset: .product(playgroundExecutableProduct.name))
                    buildSucceeded = true
                } catch {
                    print("Build failed")
                    if !playAgain {
                        break
                    }
                }

                // Hand off playground execution to the swiftpm-playground-helper
                var helperProcess: AsyncProcess? = nil

                if buildSucceeded {
                    // Build was successful so launch the playground runner executable that we just built
                    let productRelativePath = try swiftCommandState.productsBuildParameters.executablePath(for: playgroundExecutableProduct.name)
                    let helperExecutablePath = try swiftCommandState.productsBuildParameters.buildPath.appending(productRelativePath)

                    playAgain = false
                    
                    helperProcess = try self.play(
                        executablePath: helperExecutablePath,
                        originalWorkingDirectory: swiftCommandState.originalWorkingDirectory
                    )
                }

                if options.mode == .oneShot || options.list {
                    // Call playground helper then immediately exit
                    playAgain = false
                    try await helperProcess?.waitUntilExit()
                }
                else {
                    // Live updating and re-running on file changes
                    playAgain = true

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
                    
                    // Wait for either the process to finish or file changes to occur
                    let result = await withTaskGroup(of: ProcessMonitorResult.self) { group in

                        // Task to wait for process completion, if a process is running.
                        // A process won't be running if the build fails, for example, but
                        // we still want to watch for file changes below to re-build/re-run.
                        if let helperProcess {
                            group.addTask {
                                do {
                                    try await helperProcess.waitUntilExit()
                                    return .processExited
                                } catch {
                                    verboseLog("Helper process exited with error: \(error)")
                                    return .processExited
                                }
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

                        // Kill helper process, so that its task ends
                        helperProcess?.signal(SIGKILL)

                        guard let result = firstResult else {
                            // taskGroup returned no values so just return processCompleted
                            return ProcessMonitorResult.processExited
                        }

                        return result
                    }

                    #if os(macOS)
                    // Clean up file monitor after task group completes
                    fileMonitor.cancel()
                    #endif

                    switch result {
                    case .fileChanged:
                        verboseLog("Files changed, restarting...")
                        playAgain = true
                    case .processExited:
                        verboseLog("Process exited")
                        playAgain = false
                    }
                }
            } catch Diagnostics.fatalError {
                throw ExitCode.failure
            }
        } while (playAgain)
    }

    /// Executes the Playground via the specified executable at the specified path.
    private func play(
        executablePath: AbsolutePath,
        originalWorkingDirectory: AbsolutePath
    ) throws -> AsyncProcess {
        var helperArguments: [String] = []
        if options.mode == .oneShot {
            helperArguments.append("--one-shot")
        }
        helperArguments.append(options.list ? "--list" : options.playgroundName)

        let helperProcess = AsyncProcess(
            arguments: [executablePath.pathString] + helperArguments,
            workingDirectory: originalWorkingDirectory,
            outputRedirection: .none,   // don't redirect playground output (stdout/stderr)
            startNewProcessGroup: false // runner process tracks the parent process' lifetime
        )

        do {
            verboseLog("Launching runner: \(executablePath.pathString) \(helperArguments.joined(separator: " "))")
            try helperProcess.launch()
            verboseLog("Runner launched with pid \(helperProcess.processID)")
        } catch {
            print("[Helper launch failed with error: \(error)]")
            throw ExitCode.failure
        }
        
        return helperProcess
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
