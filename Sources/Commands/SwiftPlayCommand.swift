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
            try await buildSystem.build(subset: .product(playgroundExecutableProduct.name), buildOutputs: [])
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
            let signal: Int32
            #if os(Windows)
            signal = 9
            #else
            signal = SIGKILL
            #endif
            runnerProcess?.signal(signal)
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

            // Monitor for file changes (if supported)
            var fileMonitor: FileMonitor? = nil
            do {
                verboseLog("Monitoring files at \(monitorURL)")
                fileMonitor = try FileMonitor(
                    verboseLogging: globalOptions.logging.veryVerbose
                )
                try fileMonitor?.startMonitoring(atURL: monitorURL)
            } catch FileMonitor.FileMonitorError.notSupported {
                verboseLog("Monitoring files not supported on this platform")
            } catch {
                print("FileMonitor failed for \(monitorURL): \(error)")
                throw ExitCode.failure
            }

            defer {
                fileMonitor?.stopMonitoring()
            }

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

                if let fileMonitor {
                    // Task to wait for file changes
                    group.addTask {
                        await fileMonitor.waitForChanges()
                        return .fileChanged
                    }
                }

                // Return the first result from either task
                let firstResult = await group.next()

                // Cancel remaining tasks
                group.cancelAll()

                // Kill runner process, so that its task ends
                let signal: Int32
                #if os(Windows)
                signal = 9
                #else
                signal = SIGKILL
                #endif
                runnerProcess?.signal(signal)

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

// MARK: - File Monitoring -

final private class FileMonitor {
    var isMonitoring: Bool = false

    enum FileMonitorError: Error {
        case alreadyMonitoring
        case notSupported
    }

    private let verboseLogging: Bool
    private let fileWatcher: FileWatcher
    private let changeStream: AsyncStream<Void>
    private let changeContinuation: AsyncStream<Void>.Continuation

    init(verboseLogging: Bool = false) throws {
        self.verboseLogging = verboseLogging

        // Try to create a platform-specific file watcher. These aren't
        // available for every platform, in which case throw notSupported.
        guard let fileWatcher = try makeFileWatcher(verboseLogging: verboseLogging) else {
            throw FileMonitorError.notSupported
        }
        self.fileWatcher = fileWatcher

        // Create an async stream for file change notifications
        (self.changeStream, self.changeContinuation) = AsyncStream<Void>.makeStream()
    }

    deinit {
        stopMonitoring()
        changeContinuation.finish()
    }

    /// Starts monitoring for any files changes under the path at `url`.
    /// Call `waitForChanges()` to wait for any file change events.
    func startMonitoring(atURL url: URL) throws {
        guard !isMonitoring else {
            throw FileMonitorError.alreadyMonitoring
        }

        // Register files to be monitored
        try initializeMonitoring(forFilesAtURL: url)

        // Start monitoring for any file changes
        fileWatcher.startWatching {
            self.changeContinuation.yield()
        }

        isMonitoring = true
    }

    /// Stops all file monitoring.
    func stopMonitoring() {
        guard isMonitoring else { return }
        fileWatcher.stopWatching()
        isMonitoring = false
    }

    /// Recursively initializes file monitoring for a directory and all its subdirectories.
    ///
    /// This method traverses the directory structure starting from the specified URL and registers
    /// each directory (including the root directory) with the file watcher for monitoring. Hidden
    /// directories (those starting with a dot) are excluded from monitoring.
    ///
    /// - Parameter url: The root directory URL to begin monitoring. All subdirectories within
    ///                  this directory will also be monitored recursively.
    ///
    /// - Throws: An error if:
    ///   - The directory contents cannot be read
    ///   - File system access fails when checking if items are directories
    ///   - The underlying file watcher fails to monitor any directory
    ///
    /// - Note: This method excludes hidden directories (those with names starting with ".") from
    ///         monitoring to avoid watching temporary files, version control directories, and
    ///         system directories that typically don't contain user source code.
    private func initializeMonitoring(forFilesAtURL url: URL) throws {
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

        // Monitor the current directory
        try fileWatcher.register(urlToWatch: url)

        for subdirURL in subdirs {
            try fileWatcher.register(urlToWatch: subdirURL)
            try initializeMonitoring(forFilesAtURL: subdirURL)
        }
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

fileprivate protocol FileWatcher {
    init(verboseLogging: Bool) throws

    func register(urlToWatch url: URL) throws

    typealias ChangeHandler = () -> ()

    func startWatching(withChangeHandler changeHandler: @escaping ChangeHandler)

    func stopWatching()
}

fileprivate func makeFileWatcher(verboseLogging: Bool) throws -> (any FileWatcher)? {
#if os(macOS)
    return try MacFileWatcher(verboseLogging: verboseLogging)
#elseif os(Linux)
    return try LinuxFileWatcher(verboseLogging: verboseLogging)
#else
    return nil
#endif
}

#if os(macOS)

fileprivate final class MacFileWatcher: FileWatcher {
    var fileHandles: [FileHandle] = []
    var sources: [DispatchSourceFileSystemObject] = []
    var changeHandler: ChangeHandler? = nil
    let verboseLogging: Bool

    init(verboseLogging: Bool) throws {
        self.verboseLogging = verboseLogging
    }

    func register(urlToWatch url: URL) throws {
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

    func startWatching(withChangeHandler changeHandler: @escaping ChangeHandler) {
        self.changeHandler = changeHandler
    }

    func stopWatching() {
        for source in sources {
            if !source.isCancelled {
                source.cancel()
            }
        }
        self.fileHandles = []
    }

    private func process(event: DispatchSource.FileSystemEvent) {
        if verboseLogging { print("[FileMonitor event \(event)]") }
        self.changeHandler?()
    }
}

#elseif os(Linux)

fileprivate final class LinuxFileWatcher: FileWatcher {
    let inotifyFileDescriptor: Int32
    var watchDescriptors: [Int32] = []
    var monitoringTask: Task<Void, Never>?
    let verboseLogging: Bool

    init(verboseLogging: Bool = false) throws {
        self.verboseLogging = verboseLogging

        // Initialize inotify
        self.inotifyFileDescriptor = inotify_init1(Int32(IN_CLOEXEC))
        guard self.inotifyFileDescriptor != -1 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENODEV)
        }
    }

    func startWatching(withChangeHandler changeHandler: @escaping FileWatcher.ChangeHandler) {
        monitoringTask = Task {
            while !Task.isCancelled {
                // Read events from inotify
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(inotifyFileDescriptor, &buffer, buffer.count)

                if bytesRead > 0 {
                    if verboseLogging { print("[FileMonitor detected change via inotify]") }
                    changeHandler()
                } else if bytesRead == -1 {
                    if errno == EINTR || errno == EAGAIN {
                        // Interrupted or would block, continue
                        continue
                    } else {
                        // Error occurred
                        if verboseLogging { print("[FileMonitor read error: \(String(cString: strerror(errno)))]") }
                        break
                    }
                }
            }
        }
    }

    func register(urlToWatch url: URL) throws {
        let watchDescriptor = inotify_add_watch(
            inotifyFileDescriptor,
            url.path,
            UInt32(IN_MODIFY | IN_CREATE | IN_DELETE | IN_MOVE)
        )

        guard watchDescriptor != -1 else {
            throw POSIXError(.init(rawValue: errno) ?? .ENODEV)
        }

        watchDescriptors.append(watchDescriptor)

        if verboseLogging { print("[Monitoring files at \(url.path())]") }
    }

    func stopWatching() {
        monitoringTask?.cancel()

        // Remove all watch descriptors
        for watchDescriptor in watchDescriptors {
            inotify_rm_watch(inotifyFileDescriptor, watchDescriptor)
        }
        watchDescriptors.removeAll()

        // Close inotify file descriptor
        close(inotifyFileDescriptor)
    }
}

#endif
