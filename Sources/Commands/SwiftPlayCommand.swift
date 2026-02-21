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

        #if os(macOS)
        // Add rpath so the synthesized Playgrounds executable can link
        // $TOOLCHAIN/usr/lib/swift/macosx/libPlaygrounds.dylib at runtime.
        // (Despite `swiftc -print-target-info` including this path in
        // "runtimeLibraryPaths" it doesn't get included.)
        let toolchainDir = try productsBuildParameters.toolchain.toolchainDir
        let playgroundsLibPath = toolchainDir.appending(components: ["usr", "lib", "swift", "macosx"])
        productsBuildParameters.flags.linkerFlags.append(contentsOf: ["-rpath", playgroundsLibPath.pathString])
        #endif

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
        if globalOptions.logging.verbose {
            runnerArguments.append("--verbose")
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
            _verbosePlayLog(message)
        }
    }

    public init() {}
}

// MARK: - Verbose Logging -

fileprivate func _verbosePlayLog(_ message: String) {
    print("[swift play: \(message)]")
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
        // Monitor the current directory
        try fileWatcher.register(urlToWatch: url)

        // No need to register directories recursively on Windows
        // as ReadDirectoryChangesW() handles recursive subdir monitoring.
#if !os(Windows)
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
            try initializeMonitoring(forFilesAtURL: subdirURL)
        }
#endif
    }

    /// Asynchronously wait for file changes
    func waitForChanges() async {
        verboseLog("Waiting for changes")
        for await _ in changeStream {
            verboseLog("Detected change")
            // Return immediately when a change is detected
            return
        }
        // If the stream ends without yielding any values, we should still return
        // This can happen if the monitor is cancelled before any changes occur
        verboseLog("Stream ended without changes")
    }

    func verboseLog(_ message: String) {
        if verboseLogging {
            _verbosePlayLog("\(type(of: self)): \(message)")
        }
    }
}

fileprivate protocol FileWatcher {
    init(verboseLogging: Bool) throws

    var verboseLogging: Bool { get }

    func register(urlToWatch url: URL) throws

    typealias ChangeHandler = () -> ()

    func startWatching(withChangeHandler changeHandler: @escaping ChangeHandler)

    func stopWatching()
}

extension FileWatcher {
    func verboseLog(_ message: String) {
        if verboseLogging {
            _verbosePlayLog("\(type(of: self)): \(message)")
        }
    }
}

fileprivate func makeFileWatcher(verboseLogging: Bool) throws -> (any FileWatcher)? {
#if os(macOS)
    return try MacFileWatcher(verboseLogging: verboseLogging)
#elseif os(Linux)
    return try LinuxFileWatcher(verboseLogging: verboseLogging)
#elseif os(Windows)
    return try WindowsFileWatcher(verboseLogging: verboseLogging)
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
        verboseLog("stopped")
    }

    private func process(event: DispatchSource.FileSystemEvent) {
        verboseLog("FileMonitor event \(event)")
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
                    verboseLog("File watcher detected change via inotify")
                    changeHandler()
                } else if bytesRead == -1 {
                    if errno == EINTR || errno == EAGAIN {
                        // Interrupted or would block, continue
                        continue
                    } else {
                        // Error occurred
                        verboseLog("File watcher read error: \(String(cString: strerror(errno)))")
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
        verboseLog("stopped")
    }
}

#endif

#if os(Windows)

import WinSDK

fileprivate final class WindowsFileWatcher: FileWatcher {
    let verboseLogging: Bool

    private var changeHandler: ChangeHandler?
    private var monitoringTask: Task<Void, Never>?

    private typealias DirectoryWithHandle = (path: String, handle: HANDLE)
    private var registeredDirectories: [DirectoryWithHandle] = []
    
    init(verboseLogging: Bool = false) throws {
        self.verboseLogging = verboseLogging
    }
    
    func register(urlToWatch url: URL) throws {
        let directoryPath = url.path
        
        // Convert Swift string to wide character string for Windows API
        let widePath = directoryPath.withCString(encodedAs: UTF16.self) { $0 }
        
        // Open directory handle with FILE_LIST_DIRECTORY access
        let directoryHandle = CreateFileW(
            widePath,
            DWORD(FILE_LIST_DIRECTORY),
            DWORD(FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE),
            nil,
            DWORD(OPEN_EXISTING),
            DWORD(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED),
            nil
        )
        
        guard let directoryHandle, directoryHandle != INVALID_HANDLE_VALUE else {
            let error = GetLastError()
            print("[WindowsFileWatcher] Failed to open directory '\(directoryPath)' with error: \(error)")
            throw WindowsFileWatcherError.cannotOpenDirectory(path: directoryPath, errorCode: error)
        }
        
        registeredDirectories.append((path: directoryPath, handle: directoryHandle))
    }
    
    func startWatching(withChangeHandler changeHandler: @escaping ChangeHandler) {
        self.changeHandler = changeHandler
        
        monitoringTask = Task {
            await withTaskGroup(of: Void.self) { group in
                // Start monitoring each registered directory
                for registeredDirectory in registeredDirectories {
                    group.addTask {
                        await self.monitorDirectory(at: registeredDirectory)
                    }
                }
            }
        }
    }
    
    func stopWatching() {
        monitoringTask?.cancel()
        monitoringTask = nil
        
        // Close all directory handles
        for registeredDirectory in registeredDirectories {
            CloseHandle(registeredDirectory.handle)
        }
        registeredDirectories.removeAll()
        verboseLog("stopped")
    }
    
    private func monitorDirectory(at directory: DirectoryWithHandle) async {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var bytesReturned: DWORD = 0
        var overlapped = OVERLAPPED()
        
        // Create event for overlapped I/O
        overlapped.hEvent = CreateEventW(nil, true, false, nil)
        defer {
            if overlapped.hEvent != nil {
                CloseHandle(overlapped.hEvent)
            }
        }
        
        while !Task.isCancelled {
            // Start asynchronous directory change monitoring
            let success = ReadDirectoryChangesW(
                directory.handle,
                &buffer,
                DWORD(bufferSize),
                true, // bWatchSubtree - monitor subdirectories
                DWORD(FILE_NOTIFY_CHANGE_FILE_NAME | 
                      FILE_NOTIFY_CHANGE_DIR_NAME | 
                      FILE_NOTIFY_CHANGE_SIZE | 
                      FILE_NOTIFY_CHANGE_LAST_WRITE),
                &bytesReturned,
                &overlapped,
                nil
            )
            
            if !success {
                let error = GetLastError()
                if error != ERROR_IO_PENDING {
                    print("[WindowsFileWatcher] ReadDirectoryChangesW failed with error: \(error)")
                    break
                }
            }
            
            verboseLog("ReadDirectoryChangesW() successfully monitoring...")

            // Wait for the operation to complete, or timeout to check for cancellation
            let waitResult = WaitForSingleObject(overlapped.hEvent, 1000) // 1 second timeout
            
            switch waitResult {
            case DWORD(WAIT_OBJECT_0):
                // Event was signaled - changes detected
                var finalBytesReturned: DWORD = 0
                let getResult = GetOverlappedResult(directory.handle, &overlapped, &finalBytesReturned, false)
                
                if getResult && finalBytesReturned > 0 {

                    // Parse the buffer to extract file change information
                    let changedFiles = parseFileChangeBuffer(buffer: buffer, bytesReturned: Int(finalBytesReturned))
                    verboseLog("Detected change(s): \(changedFiles.map {(action, filename) in actionDescription(for: action) + " - " + filename}.joined(separator: ","))")

                    // Filter out changes that weren't not interested in
                    let interestedChanges = changedFiles.filter { (action, filename) in
                        // Ignore any ".build" directories
                        if filename.starts(with: ".build") {
                            return false
                        }
                        return true
                    }

                    if interestedChanges.count > 0 {
                        changeHandler?()
                    }
                }
                else {
                    verboseLog("GetOverlappedResult() returned \(getResult), finalBytesReturned=\(finalBytesReturned) - ignoring event")
                }
                
                // Reset the event for next iteration
                ResetEvent(overlapped.hEvent)
                
            case DWORD(WAIT_TIMEOUT):
                // Timeout occurred, continue monitoring
                verboseLog("Timeout, continue monitoring")
                continue
                
            default:
                // Error or other result
                verboseLog("[WindowsFileWatcher] WaitForSingleObject returned unexpected value: \(waitResult)")
                break
            }
        }
    }

    /// Parses the buffer returned by ReadDirectoryChangesW to extract file change information.
    /// 
    /// The buffer contains one or more FILE_NOTIFY_INFORMATION structures:
    /// - NextEntryOffset: DWORD (offset to next record, 0 for last record)
    /// - Action: DWORD (type of change that occurred)
    /// - FileNameLength: DWORD (length of filename in bytes)
    /// - FileName: WCHAR[] (wide character filename, not null-terminated)
    ///
    /// - Parameters:
    ///   - buffer: The buffer filled by ReadDirectoryChangesW
    ///   - bytesReturned: The number of valid bytes in the buffer
    /// - Returns: Array of tuples containing (action, fileName)
    private func parseFileChangeBuffer(buffer: [UInt8], bytesReturned: Int) -> [(DWORD, String)] {
        var results: [(DWORD, String)] = []
        var offset = 0
        
        while offset < bytesReturned {
            // Ensure we have enough bytes for the fixed part of FILE_NOTIFY_INFORMATION
            guard offset + 12 <= bytesReturned else { break }
            
            // Read the FILE_NOTIFY_INFORMATION structure
            let nextEntryOffset = buffer.withUnsafeBufferPointer { bufferPtr in
                bufferPtr.baseAddress!.advanced(by: offset).withMemoryRebound(to: DWORD.self, capacity: 1) { $0.pointee }
            }
            
            let action = buffer.withUnsafeBufferPointer { bufferPtr in
                bufferPtr.baseAddress!.advanced(by: offset + 4).withMemoryRebound(to: DWORD.self, capacity: 1) { $0.pointee }
            }
            
            let fileNameLength = buffer.withUnsafeBufferPointer { bufferPtr in
                bufferPtr.baseAddress!.advanced(by: offset + 8).withMemoryRebound(to: DWORD.self, capacity: 1) { $0.pointee }
            }
            
            // Ensure we have enough bytes for the filename
            let fileNameStart = offset + 12
            let fileNameEnd = fileNameStart + Int(fileNameLength)
            guard fileNameEnd <= bytesReturned else { break }
            
            // Extract the wide character filename and convert to String
            let fileName = buffer.withUnsafeBufferPointer { bufferPtr in
                let wideCharPtr = bufferPtr.baseAddress!.advanced(by: fileNameStart).withMemoryRebound(to: UInt16.self, capacity: Int(fileNameLength / 2)) { $0 }
                let wideCharCount = Int(fileNameLength / 2)
                
                // Create a String from the UTF-16 encoded wide characters
                return String(utf16CodeUnits: wideCharPtr, count: wideCharCount)
            }
            
            results.append((action, fileName))
            
            // Move to the next record
            if nextEntryOffset == 0 {
                break // This was the last record
            }
            offset += Int(nextEntryOffset)
        }
        
        return results
    }
    
    /// Converts a Windows file notification action code to a human-readable description.
    private func actionDescription(for action: DWORD) -> String {
        switch action {
        case DWORD(FILE_ACTION_ADDED):
            return "File added"
        case DWORD(FILE_ACTION_REMOVED):
            return "File removed"
        case DWORD(FILE_ACTION_MODIFIED):
            return "File modified"
        case DWORD(FILE_ACTION_RENAMED_OLD_NAME):
            return "File renamed (old name)"
        case DWORD(FILE_ACTION_RENAMED_NEW_NAME):
            return "File renamed (new name)"
        default:
            return "Unknown action (\(action))"
        }
    }
}

enum WindowsFileWatcherError: Error {
    case cannotOpenDirectory(path: String, errorCode: DWORD)
}

#endif
