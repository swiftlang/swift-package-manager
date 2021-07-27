/*
This source file is part of the Swift.org open source project

Copyright 2015 - 2016 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import Build
import PackageGraph
import PackageModel
import TSCBasic
import ScriptParse
import ScriptingCore
import Foundation

public extension SwiftToolOptions {
    func redirect(to dir: AbsolutePath) throws -> SwiftToolOptions {
        var options = self
        options.packagePath = dir
        options.buildPath = nil
        try options.validate()
        return options
    }
}

struct ScriptToolOptions: ParsableArguments {
    /// If the executable product should be built before running.
    @Flag(name: .customLong("skip-build"), help: "Skip building the executable product")
    var shouldSkipBuild: Bool = false
    
    /// Whether to print build progress.
    @Flag(help: "Print build progress")
    var quiet: Bool = false

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
    struct Run: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Runs a script")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: ScriptToolOptions
        
        func run() throws {
            guard let file = options.file else {
                throw ScriptError.fileNotFound("")
            }
            let (productName, cacheDirPath) = try prepareCache(for: file, at: SwiftScriptTool.cacheDir)

            let swiftTool = try SwiftTool(options: swiftOptions.redirect(to: cacheDirPath))
            swiftTool.redirectStdoutToStderr()
            let output = BufferedOutputByteStream()
            if options.quiet {
                swiftTool.redirectStdoutTo(.init(output))
            }

            do {
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
