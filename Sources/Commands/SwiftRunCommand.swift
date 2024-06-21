//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2015-2016 Apple Inc. and the Swift project authors
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

import enum TSCBasic.ProcessEnv
import func TSCBasic.exec

import enum TSCUtility.Diagnostics

/// An enumeration of the errors that can be generated by the run tool.
private enum RunError: Swift.Error {
    /// The package manifest has no executable product.
    case noExecutableFound

    /// Could not find a specific executable in the package manifest.
    case executableNotFound(String)

    /// There are multiple executables and one must be chosen.
    case multipleExecutables([String])
}

extension RunError: CustomStringConvertible {
    var description: String {
        switch self {
        case .noExecutableFound:
            return "no executable product available"
        case .executableNotFound(let executable):
            return "no executable product named '\(executable)'"
        case .multipleExecutables(let executables):
            let joinedExecutables = executables.joined(separator: ", ")
            return "multiple executable products available: \(joinedExecutables)"
        }
    }
}

struct RunCommandOptions: ParsableArguments {
    enum RunMode: EnumerableFlag {
        case repl
        case debugger
        case run

        static func help(for value: RunCommandOptions.RunMode) -> ArgumentHelp? {
            switch value {
            case .repl:
                return "Launch Swift REPL for the package"
            case .debugger:
                return "Launch the executable in a debugger session"
            case .run:
                return "Launch the executable with the provided arguments"
            }
        }
    }

    /// The mode in with the tool command should run.
    @Flag var mode: RunMode = .run

    /// If the executable product should be built before running.
    @Flag(name: .customLong("skip-build"), help: "Skip building the executable product")
    var shouldSkipBuild: Bool = false

    var shouldBuild: Bool { !shouldSkipBuild }

    /// If the test should be built.
    @Flag(name: .customLong("build-tests"), help: "Build both source and test targets")
    var shouldBuildTests: Bool = false

    /// The executable product to run.
    @Argument(help: "The executable to run", completion: .shellCommand("swift package completion-tool list-executables"))
    var executable: String?

    /// Specifies the traits to build the product with.
    @OptionGroup(visibility: .hidden)
    package var traits: TraitOptions

    /// The arguments to pass to the executable.
    @Argument(parsing: .captureForPassthrough,
              help: "The arguments to pass to the executable")
    var arguments: [String] = []
}

/// swift-run command namespace
public struct SwiftRunCommand: AsyncSwiftCommand {
    public static var configuration = CommandConfiguration(
        commandName: "run",
        _superCommandName: "swift",
        abstract: "Build and run an executable product",
        discussion: "SEE ALSO: swift build, swift package, swift test",
        version: SwiftVersion.current.completeDisplayString,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    public var globalOptions: GlobalOptions

    @OptionGroup()
    var options: RunCommandOptions

    public var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
        return .init(wantsREPLProduct: options.mode == .repl)
    }

    public func run(_ swiftCommandState: SwiftCommandState) async throws {
        if options.shouldBuildTests && options.shouldSkipBuild {
            swiftCommandState.observabilityScope.emit(
              .mutuallyExclusiveArgumentsError(arguments: ["--build-tests", "--skip-build"])
            )
            throw ExitCode.failure
        }

        switch options.mode {
        case .repl:
            // Load a custom package graph which has a special product for REPL.
            let graphLoader = {
                try swiftCommandState.loadPackageGraph(
                    explicitProduct: self.options.executable
                )
            }

            // Construct the build operation.
            // FIXME: We need to implement the build tool invocation closure here so that build tool plugins work with the REPL. rdar://86112934
            let buildSystem = try swiftCommandState.createBuildSystem(
                explicitBuildSystem: .native,
                traitConfiguration: .init(traitOptions: self.options.traits),
                cacheBuildManifest: false,
                packageGraphLoader: graphLoader
            )

            // Perform build.
            try buildSystem.build()

            // Execute the REPL.
            let arguments = try buildSystem.buildPlan.createREPLArguments()
            print("Launching Swift REPL with arguments: \(arguments.joined(separator: " "))")
            try self.run(
                fileSystem: swiftCommandState.fileSystem,
                executablePath: swiftCommandState.getTargetToolchain().swiftInterpreterPath,
                originalWorkingDirectory: swiftCommandState.originalWorkingDirectory,
                arguments: arguments
            )

        case .debugger:
            do {
                let buildSystem = try swiftCommandState.createBuildSystem(
                    explicitProduct: options.executable,
                    traitConfiguration: .init(traitOptions: self.options.traits)
                )
                let productName = try findProductName(in: buildSystem.getPackageGraph())
                if options.shouldBuildTests {
                    try buildSystem.build(subset: .allIncludingTests)
                } else if options.shouldBuild {
                    try buildSystem.build(subset: .product(productName))
                }

                let executablePath = try swiftCommandState.productsBuildParameters.buildPath.appending(component: productName)

                // Make sure we are running from the original working directory.
                let cwd: AbsolutePath? = swiftCommandState.fileSystem.currentWorkingDirectory
                if cwd == nil || swiftCommandState.originalWorkingDirectory != cwd {
                    try ProcessEnv.chdir(swiftCommandState.originalWorkingDirectory)
                }

                let pathRelativeToWorkingDirectory = executablePath.relative(to: swiftCommandState.originalWorkingDirectory)
                let lldbPath = try swiftCommandState.getTargetToolchain().getLLDB()
                try exec(path: lldbPath.pathString, args: ["--", pathRelativeToWorkingDirectory.pathString] + options.arguments)
            } catch let error as RunError {
                swiftCommandState.observabilityScope.emit(error)
                throw ExitCode.failure
            }

        case .run:
            // Detect deprecated uses of swift run to interpret scripts.
            if let executable = options.executable, try isValidSwiftFilePath(fileSystem: swiftCommandState.fileSystem, path: executable) {
                swiftCommandState.observabilityScope.emit(.runFileDeprecation)
                // Redirect execution to the toolchain's swift executable.
                let swiftInterpreterPath = try swiftCommandState.getTargetToolchain().swiftInterpreterPath
                // Prepend the script to interpret to the arguments.
                let arguments = [executable] + options.arguments
                try self.run(
                    fileSystem: swiftCommandState.fileSystem,
                    executablePath: swiftInterpreterPath,
                    originalWorkingDirectory: swiftCommandState.originalWorkingDirectory,
                    arguments: arguments
                )
                return
            }

            do {
                let buildSystem = try swiftCommandState.createBuildSystem(
                    explicitProduct: options.executable,
                    traitConfiguration: .init(traitOptions: self.options.traits)
                )
                let productName = try findProductName(in: buildSystem.getPackageGraph())
                if options.shouldBuildTests {
                    try buildSystem.build(subset: .allIncludingTests)
                } else if options.shouldBuild {
                    try buildSystem.build(subset: .product(productName))
                }

                let executablePath = try swiftCommandState.productsBuildParameters.buildPath.appending(component: productName)
                try self.run(
                    fileSystem: swiftCommandState.fileSystem,
                    executablePath: executablePath,
                    originalWorkingDirectory: swiftCommandState.originalWorkingDirectory,
                    arguments: options.arguments
                )
            } catch Diagnostics.fatalError {
                throw ExitCode.failure
            } catch let error as RunError {
                swiftCommandState.observabilityScope.emit(error)
                throw ExitCode.failure
            }
        }
    }

    /// Returns the path to the correct executable based on options.
    private func findProductName(in graph: ModulesGraph) throws -> String {
        if let executable = options.executable {
            // There should be only one product with the given name in the graph
            // and it should be executable or snippet.
            guard let product = graph.product(for: executable, destination: .destination),
                  product.type == .executable || product.type == .snippet
            else {
                throw RunError.executableNotFound(executable)
            }
            return executable
        }

        // If the executable is implicit, search through root products.
        let rootExecutables = graph.rootPackages
            .flatMap { $0.products }
            .filter { $0.type == .executable || $0.type == .snippet }
            .map { $0.name }

        // Error out if the package contains no executables.
        guard rootExecutables.count > 0 else {
            throw RunError.noExecutableFound
        }

        // Only implicitly deduce the executable if it is the only one.
        guard rootExecutables.count == 1 else {
            throw RunError.multipleExecutables(rootExecutables)
        }

        return rootExecutables[0]
    }

    /// Executes the executable at the specified path.
    private func run(
        fileSystem: FileSystem,
        executablePath: AbsolutePath,
        originalWorkingDirectory: AbsolutePath,
        arguments: [String]) throws
    {
        // Make sure we are running from the original working directory.
        let cwd: AbsolutePath? = fileSystem.currentWorkingDirectory
        if cwd == nil || originalWorkingDirectory != cwd {
            try ProcessEnv.chdir(originalWorkingDirectory)
        }

        let pathRelativeToWorkingDirectory = executablePath.relative(to: originalWorkingDirectory)
        try execute(path: executablePath.pathString, args: [pathRelativeToWorkingDirectory.pathString] + arguments)
    }

    /// Determines if a path points to a valid swift file.
    private func isValidSwiftFilePath(fileSystem: FileSystem, path: String) throws -> Bool {
        guard path.hasSuffix(".swift") else { return false }
        //FIXME: Return false when the path is not a valid path string.
        let absolutePath: AbsolutePath
        if path.first == "/" {
            do {
                absolutePath = try AbsolutePath(validating: path)
            } catch {
                return false
            }
        } else {
            guard let cwd = fileSystem.currentWorkingDirectory else {
                return false
            }
            absolutePath = try AbsolutePath(cwd, validating: path)
        }
        return fileSystem.isFile(absolutePath)
    }

    /// A safe wrapper of TSCBasic.exec.
    private func execute(path: String, args: [String]) throws -> Never {
        #if !os(Windows)
        // Dispatch will disable almost all asynchronous signals on its worker threads, and this is called from `async`
        // context. To correctly `exec` a freshly built binary, we will need to:
        // 1. reset the signal masks
        for i in 1..<NSIG {
            signal(i, SIG_DFL)
        }
        var sig_set_all = sigset_t()
        sigfillset(&sig_set_all)
        sigprocmask(SIG_UNBLOCK, &sig_set_all, nil)

        #if os(Android)
        let number_fds = Int32(sysconf(_SC_OPEN_MAX))
        #else
        let number_fds = getdtablesize()
        #endif
        
        // 2. close all file descriptors.
        for i in 3..<number_fds {
            close(i)
        }
        #endif

        try TSCBasic.exec(path: path, args: args)
    }

    public init() {}
}

private extension Basics.Diagnostic {
    static var runFileDeprecation: Self {
        .warning("'swift run file.swift' command to interpret swift files is deprecated; use 'swift file.swift' instead")
    }
}

