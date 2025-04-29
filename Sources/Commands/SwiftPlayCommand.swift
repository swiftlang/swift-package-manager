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

    /// Output debug logging for play command
    @Flag(name: .customLong("enable-play-debug-logging"), help: "Output debug logging for the play command")
    var debugLoggingEnabled: Bool = false

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
        // Enabling REPL product ensures products are built as dynamic libraries
        // so that swiftpm-playground-helper can load them.
        return .init(wantsREPLProduct: true)
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
                if options.debugLoggingEnabled {
                    for product in allProducts {
                        print("[Found product: \(product)]")
                    }
                    print("[- Found \(allProducts.count) product\(allProducts.count==1 ? "" : "s")]")
                }

                let filteredProducts = allProducts.filter {
                    // Only library targets are supported for playgrounds right now
                    $0.type.isLibrary && $0.modules.count > 0 && !$0.isLinkingXCTest
                }
                if options.debugLoggingEnabled {
                    for product in filteredProducts {
                        print("[Filtered product: \(product)]")
                    }
                    print("[- Filtered down to \(filteredProducts.count) product\(filteredProducts.count==1 ? "" : "s")]")
                }

                // Choose the "REPL" product
                guard let playgroundLibraryProduct = filteredProducts.first(where: { $0.name.hasSuffix(Product.replProductSuffix) }) else {
                    print("No product found that matches criteria for hosting playgrounds")
                    throw ExitCode.failure
                }
                if options.debugLoggingEnabled { print("[Choosing product \"\(playgroundLibraryProduct.name)\", type: \(playgroundLibraryProduct.type)]") }

                guard case .library(_) = playgroundLibraryProduct.type else {
                    print("Product \"\(playgroundLibraryProduct.name)\" is not a library (it's a \(playgroundLibraryProduct.type)) and so cannot be used for playgrounds")
                    throw ExitCode.failure
                }

                let buildConfigurationDirName = try swiftCommandState.productsBuildParameters.configuration.dirname
                let playgroundHelperArguments = [
                    "--lib-path",
                    "\(swiftCommandState.scratchDirectory)/\(buildConfigurationDirName)/lib\(playgroundLibraryProduct.name).dylib"
                ]

                // Build the package
                var buildSucceeded = false
                do {
                    try await buildSystem.build(subset: .product(playgroundLibraryProduct.name))
                    buildSucceeded = true
                } catch {
                    print("Build failed")
                    if !playAgain {
                        break
                    }
                }

                // Hand off playground execution to the swiftpm-playground-helper
                var helperProcess: Process? = nil
                
                if buildSucceeded {
                    // Build was successful so call swiftpm-playground-helper to list or run playgrounds
                    var helperExecutablePath: AbsolutePath
                    if let helperOverridePath = ProcessInfo.processInfo.environment["SWIFTPM_PLAYGROUND_HELPER"],
                       let helperOverrideAbsolutePath = AbsolutePath(argument: helperOverridePath) {
                        helperExecutablePath = helperOverrideAbsolutePath
                    }
                    else {
                        let toolchain = try swiftCommandState.getTargetToolchain()
                        helperExecutablePath = try toolchain.getSwiftPlaygroundHelper()
                    }

                    playAgain = false
                    
                    helperProcess = try self.play(
                        fileSystem: swiftCommandState.fileSystem,
                        executablePath: helperExecutablePath,
                        originalWorkingDirectory: swiftCommandState.originalWorkingDirectory,
                        playgroundHelperArguments: playgroundHelperArguments
                    )
                }
                
                // Watch files for live updating
                
                guard let monitorURL = swiftCommandState.fileSystem.currentWorkingDirectory?.asURL else {
                    print("[No cwd]")
                    throw ExitCode.failure
                }
                
                switch options.mode {
                case .oneShot:
                    playAgain = false
                    helperProcess?.waitUntilExit()

                case .liveUpdate:
                    playAgain = true
                    
                    // Monitor for file changes
                    var fileMonitor: FileMonitor? = nil
                    do {
                        if options.debugLoggingEnabled { print("[Monitoring files at \(monitorURL)]") }
                        fileMonitor = try FileMonitor(url: monitorURL)
                    } catch {
                        print("[FileMonitor failed for \(monitorURL): \(error)]")
                        throw ExitCode.failure
                    }
                    defer {
                        fileMonitor?.cancel()
                        fileMonitor = nil
                    }
                    
                    if options.debugLoggingEnabled { print("[swift play waiting...]") }
                    var waitingForFileChanges = true
                    
                    fileMonitor?.onChange = {
                        if options.debugLoggingEnabled { print("[Files changed]") }
                        waitingForFileChanges = false
                    }
                    while(waitingForFileChanges) {
                        sleep(1)
                        
                        // If Playground was running and it finished then stop playing
                        if let activeProcess = helperProcess, !activeProcess.isRunning {
                            waitingForFileChanges = false
                            playAgain = false
                        }
                    }
                }

                if let activeProcess = helperProcess, activeProcess.processIdentifier > 0 {
                    if options.debugLoggingEnabled { print("[killing pid \(activeProcess.processIdentifier)]") }
                    kill(activeProcess.processIdentifier, SIGKILL)
                }
                helperProcess = nil
                
            } catch Diagnostics.fatalError {
                throw ExitCode.failure
            }
        } while (playAgain)
    }

    /// Executes the Playground via the specified executable at the specified path.
    private func play(
        fileSystem: FileSystem,
        executablePath: AbsolutePath,
        originalWorkingDirectory: AbsolutePath,
        playgroundHelperArguments: [String]) throws -> Process
    {
        // Make sure we are running from the original working directory.
        let cwd: AbsolutePath? = fileSystem.currentWorkingDirectory
        if cwd == nil || originalWorkingDirectory != cwd {
            try ProcessEnv.chdir(originalWorkingDirectory)
        }

        var extraArguments: [String] = []
        if options.mode == .oneShot {
            extraArguments.append("--one-shot")
        }
        extraArguments.append(options.list ? "--list" : options.playgroundName)
        
        let allArguments = playgroundHelperArguments + extraArguments
        let helperProcess = Process()
        helperProcess.executableURL = executablePath.asURL
        helperProcess.arguments = allArguments

        do {
            if options.debugLoggingEnabled { print("[Launching helper: \(executablePath.pathString) \(allArguments.joined(separator: " "))]") }
            try helperProcess.run()
            tcsetpgrp(STDIN_FILENO, helperProcess.processIdentifier)
            if options.debugLoggingEnabled { print("[Helper launched with pid \(helperProcess.processIdentifier)]") }
        } catch {
            print("[Helper launch failed with error: \(error)]")
            throw ExitCode.failure
        }
        
        return helperProcess
    }

    public init() {}
}

final private class FileMonitor {
    
    let url: URL
    var fileHandles: [FileHandle] = []
    var sources: [DispatchSourceFileSystemObject] = []
    
    typealias OnChange = () -> ()
    var onChange: OnChange? = nil
    var verbose = false

    init(url: URL) throws {
        self.url = url
        
        try initializeMonitoring(for: url)
    }
    
    private func initializeMonitoring(for url: URL) throws {
        let directoryContents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let subdirs = directoryContents
            .filter { $0.lastPathComponent.hasPrefix(".") == false }
            .filter { url in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.relativePath, isDirectory: &isDir) {
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
            queue: DispatchQueue.main
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

        if verbose { print("[Monitoring files at \(url.path())]") }
    }

    func cancel() {
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
    
    func process(event: DispatchSource.FileSystemEvent) {
        if verbose { print("Event \(event) for \(url.path())") }
        if let onChange {
            onChange()
        }
    }
}
