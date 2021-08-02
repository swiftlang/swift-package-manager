/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import PackageModel
import TSCBasic
import ScriptParse
import ScriptingCore
import Workspace

struct ScriptToolOptions: ParsableArguments {
    /// If the executable product should be built before running.
    @Flag(name: .customLong("skip-build"), help: "Skip building the executable product")
    var shouldSkipBuild: Bool = false

    var shouldBuild: Bool { !shouldSkipBuild }

    /// The script file to run.
    @Argument(help: "The script file to run")
    var file: String?

    /// The arguments to pass to the executable.
    @Argument(parsing: .unconditionalRemaining,
              help: "The arguments to pass to the executable")
    var arguments: [String] = []
}

/// swift-script tool namespace
public struct SwiftScriptTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "script",
        _superCommandName: "swift",
        abstract: "Manage and run Swift scripts",
        discussion: "SEE ALSO: swift build, swift run, swift package, swift test",
        version: SwiftVersion.currentVersion.completeDisplayString,
        subcommands: [
            Run.self,
            Build.self,
            Clean.self,
            Reset.self,
            Resolve.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

//    @OptionGroup()
//    var swiftOptions: SwiftToolOptions
//
//    @OptionGroup()
//    var options: ScriptToolOptions

    public init() {}

    public static var _errorLabel: String { "error" }
}

extension SwiftScriptTool {
    static var cacheDir: AbsolutePath { localFileSystem.dotSwiftPM.appending(component: "scripts") }
}

/// swift-run tool namespace
extension SwiftScriptTool {
    struct Run: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Runs a script")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions

        /// Whether to print build progress.
        @Flag(help: "Print build progress")
        var quiet: Bool = false
        
        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            let output = BufferedOutputByteStream()
            if quiet {
                swiftTool.redirectStdoutTo(.init(output))
            } else {
                swiftTool.redirectStdoutToStderr()
            }

            do {
                // FIXME: How to hide the note?
                swiftTool.diagnostics.emit(note: "Using cache: \(cacheDirPath.basename)")
                let buildSystem = try swiftTool.createBuildSystem(explicitProduct: nil)
                if options.shouldBuild {
                    try buildSystem.build(subset: .product(productName))
                }

                let executablePath = try swiftTool.buildParameters().buildPath.appending(component: productName)
                try Commands.run(executablePath,
                        originalWorkingDirectory: swiftTool.originalWorkingDirectory,
                        arguments: options.arguments)
            } catch let error as ScriptError {
                swiftTool.diagnostics.emit(error)
                stderrStream <<< output.bytes
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }

    struct Build: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Prebuild a script")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions
        
        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            swiftTool.redirectStdoutToStderr()

            do {
                swiftTool.diagnostics.emit(note: "Using cache: \(cacheDirPath.basename)")
                let buildSystem = try swiftTool.createBuildSystem(explicitProduct: nil)
                if options.shouldBuild {
                    try buildSystem.build(subset: .product(productName))
                }
            } catch let error as ScriptError {
                swiftTool.diagnostics.emit(error)
                throw ExitCode.failure
            }
        }
    }
}

extension SwiftScriptTool {
    struct Clean: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions
        
        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            try swiftTool.getActiveWorkspace().clean(with: swiftTool.diagnostics)
        }
    }

    struct Reset: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache directory")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions
        
        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            try localFileSystem.removeFileTree(cacheDirPath)
        }
    }
    
    struct Update: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions
        
        @Flag(name: [.long, .customShort("n")],
              help: "Display the list of dependencies that can be updated")
        var dryRun: Bool = false
        
        @Argument(help: "The packages to update")
        var packages: [String] = []

        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            let workspace = try swiftTool.getActiveWorkspace()

            let changes = try workspace.updateDependencies(
                root: swiftTool.getWorkspaceRoot(),
                packages: packages,
                diagnostics: swiftTool.diagnostics,
                dryRun: dryRun
            )

            // try to load the graph which will emit any errors
            if !swiftTool.diagnostics.hasErrors {
                _ = try workspace.loadPackageGraph(
                    rootInput: swiftTool.getWorkspaceRoot(),
                    diagnostics: swiftTool.diagnostics
                )
            }

            if let pinsStore = swiftTool.diagnostics.wrap({ try workspace.pinsStore.load() }),
               let changes = changes, dryRun {
                logPackageChanges(changes: changes, pins: pinsStore)
            }

            if !dryRun {
                // Throw if there were errors when loading the graph.
                // The actual errors will be printed before exiting.
                guard !swiftTool.diagnostics.hasErrors else {
                    throw ExitCode.failure
                }
            }
        }
    }
}

extension SwiftScriptTool {
    struct ResolveOptions: ParsableArguments {
        @Option(help: "The version to resolve at", transform: { Version(string: $0) })
        var version: Version?
        
        @Option(help: "The branch to resolve at")
        var branch: String?
        
        @Option(help: "The revision to resolve at")
        var revision: String?

        @Argument(help: "The name of the package to resolve")
        var packageName: String?
    }
    
    struct Resolve: ScriptCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resolve package dependencies")
        
        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions
        
        func run(_ swiftTool: SwiftTool, as productName: String, at cacheDirPath: AbsolutePath) throws {
            // If a package is provided, use that to resolve the dependencies.
            if let packageName = resolveOptions.packageName {
                let workspace = try swiftTool.getActiveWorkspace()
                try workspace.resolve(
                    packageName: packageName,
                    root: swiftTool.getWorkspaceRoot(),
                    version: resolveOptions.version,
                    branch: resolveOptions.branch,
                    revision: resolveOptions.revision,
                    diagnostics: swiftTool.diagnostics)
                if swiftTool.diagnostics.hasErrors {
                    throw ExitCode.failure
                }
            } else {
                // Otherwise, run a normal resolve.
                try swiftTool.resolve()
            }
        }
    }
}

/// Executes the executable at the specified path.
fileprivate func run(
    _ excutablePath: AbsolutePath,
    originalWorkingDirectory: AbsolutePath,
    arguments: [String]) throws {
    // Make sure we are running from the original working directory.
    let cwd: AbsolutePath? = localFileSystem.currentWorkingDirectory
    if cwd == nil || originalWorkingDirectory != cwd {
        try ProcessEnv.chdir(originalWorkingDirectory)
    }

    let pathRelativeToWorkingDirectory = excutablePath.relative(to: originalWorkingDirectory)
    try exec(path: excutablePath.pathString, args: [pathRelativeToWorkingDirectory.pathString] + arguments)
}

/// Logs all changed dependencies to a stream
/// - Parameter changes: Changes to log
/// - Parameter pins: PinsStore with currently pinned packages to compare changed packages to.
/// - Parameter stream: Stream used for logging
fileprivate func logPackageChanges(changes: [(PackageReference, Workspace.PackageStateChange)], pins: PinsStore, on stream: OutputByteStream = TSCBasic.stdoutStream) {
    let changes = changes.filter { $0.1 != .unchanged }
    
    stream <<< "\n"
    stream <<< "\(changes.count) dependenc\(changes.count == 1 ? "y has" : "ies have") changed\(changes.count > 0 ? ":" : ".")"
    stream <<< "\n"
    
    for (package, change) in changes {
        let currentVersion = pins.pinsMap[package.identity]?.state.description ?? ""
        switch change {
        case let .added(state):
            stream <<< "+ \(package.name) \(state.requirement.prettyPrinted)"
        case let .updated(state):
            stream <<< "~ \(package.name) \(currentVersion) -> \(package.name) \(state.requirement.prettyPrinted)"
        case .removed:
            stream <<< "- \(package.name) \(currentVersion)"
        case .unchanged:
            continue
        }
        stream <<< "\n"
    }
    stream.flush()
}
