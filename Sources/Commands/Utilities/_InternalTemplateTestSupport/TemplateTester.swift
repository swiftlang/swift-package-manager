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

import ArgumentParserToolInfo

import Basics
import CoreCommands
import Foundation
import PackageGraph
import PackageModel
import SPMBuildCore
import Workspace
@_spi(PackageRefactor) import SwiftRefactor

/// Context containing all necessary state and configuration for testing a Swift template.
public class TemplateTesterContext {
    /// The Swift command state containing build configuration and observability scope.
    let swiftCommandState: SwiftCommandState

    /// The base package structure type before invoking the template's executable
    let initialPackageType: InitPackage.PackageType

    /// The current working directory.
    let cwd: Basics.AbsolutePath

    /// The build system provider kind to use for building template dependencies.
    let buildSystem: BuildSystemProvider.Kind

    /// The output directory where generated templates will be written.
    var outputDirectory: Basics.AbsolutePath

    /// Options for building the generated template.
    var buildCommandOptions: BuildCommandOptions

    /// Determines the format in which test output is displayed.
    var format: ShowTestTemplateOutput

    /// Initializes a new context for template testing.
    ///
    /// - Parameters:
    ///   - swiftCommandState: The Swift command state containing build configuration and observability.
    ///   - initialPackageType: The type of package to create when initializing the template.
    ///   - cwd: The working directory from which the template is executed.
    ///   - buildSystem: The build system to use for compiling the generated template.
    ///   - outputDirectory: The directory where generated files will be placed.
    ///   - buildCommandOptions: Options to use when building the template.
    ///   - format: Format for displaying test output (`matrix` or `json`).
    init(
        swiftCommandState: SwiftCommandState,
        initialPackageType: InitPackage.PackageType,
        cwd: Basics.AbsolutePath,
        buildSystem: BuildSystemProvider.Kind,
        outputDirectory: Basics.AbsolutePath,
        buildCommandOptions: BuildCommandOptions,
        format: ShowTestTemplateOutput
    ) {
        self.swiftCommandState = swiftCommandState
        self.initialPackageType = initialPackageType
        self.cwd = cwd
        self.buildSystem = buildSystem
        self.outputDirectory = outputDirectory
        self.buildCommandOptions = buildCommandOptions
        self.format = format
    }
}

/// A tester for Swift templates that allows generating, building, and verifying template outputs.
///
/// `TemplateTester` coordinates the entire process of testing a Swift template:
/// - Initializes the template in a temporary or provided directory
/// - Executes the template plugin
/// - Builds the generated template
/// - Captures output, logs, and duration for generation and build steps
public struct TemplateTester {
    /// The Swift command state containing build configuration and observability scope.
    let swiftCommandState: SwiftCommandState

    /// The base package structure type before invoking the template's executable
    private let initialPackageType: InitPackage.PackageType

    /// The resolved command-line  plugin module.
    private let commandPlugin: ResolvedModule

    /// The current working directory.
    private let cwd: Basics.AbsolutePath

    /// The build system provider kind to use for building template dependencies.
    private let buildSystem: BuildSystemProvider.Kind

    /// The output directory where generated templates will be written.
    private var outputDirectory: Basics.AbsolutePath

    /// Options for building the generated template.
    private var buildCommandOptions: BuildCommandOptions

    /// Determines the format in which test output is displayed.
    private var format: ShowTestTemplateOutput

    /// Initializes a new template tester with the given plugin and context.
    ///
    /// - Parameters:
    ///   - commandPlugin: The resolved Swift plugin module for the template.
    ///   - templateTesterContext: Context containing configuration and environment for template testing.
    init(
        commandPlugin: ResolvedModule,
        templateTesterContext: TemplateTesterContext
    ) {
        self.swiftCommandState = templateTesterContext.swiftCommandState
        self.initialPackageType = templateTesterContext.initialPackageType
        self.commandPlugin = commandPlugin
        self.cwd = templateTesterContext.cwd
        self.buildSystem = templateTesterContext.buildSystem
        self.outputDirectory = templateTesterContext.outputDirectory
        self.buildCommandOptions = templateTesterContext.buildCommandOptions
        self.format = templateTesterContext.format
    }

    /// Tests a template across multiple decision tree branches.
    ///
    /// Each branch represents a unique combination of command-line arguments. This method:
    /// - Generates the template
    /// - Builds the generated template
    /// - Captures logs and durations
    /// - Outputs a matrix or JSON of results depending on the `format` setting
    ///
    /// - Parameter templateCommandPaths: Dictionary mapping branch names to their argument arrays.
    /// - Throws: Any error encountered during template generation or building.
    func testTemplateWith(templateCommandPaths: [String: [String]]) async throws {
        var buildMatrix: [String: TestTemplateResult] = [:]

        for branch in templateCommandPaths {
            let folderName = branch.key
            buildMatrix[folderName] = try await self.testDecisionTreeBranch(
                decisionPath: folderName,
                args: branch.value
            )
        }

        switch self.format {
        case .matrix:
            TestTemplateResult.printBuildMatrix(buildMatrix)
        case .json:
            TestTemplateResult.printJSONMatrix(buildMatrix)
        }
    }

    /// Tests a single branch of template execution.
    ///
    /// - Parameters:
    ///   - decisionPath: Name of the branch.
    ///   - args: Command-line arguments for this branch.
    /// - Returns: `TestTemplateInfo` containing success/failure, duration, and log paths.
    /// - Throws: Any error encountered during template generation or build.
    func testDecisionTreeBranch(decisionPath: String, args: [String]) async throws -> TestTemplateResult {
        let destinationPath = self.outputDirectory.appending(component: decisionPath)

        self.swiftCommandState.observabilityScope.emit(debug: "Generating \(decisionPath)")
        do {
            try FileManager.default.createDirectory(at: destinationPath.asURL, withIntermediateDirectories: true)
        } catch {
            throw TestTemplateCommandError.directoryCreationFailed(destinationPath.pathString)
        }

        return try await self.testTemplateInitialization(
            commandPlugin: self.commandPlugin,
            swiftCommandState: self.swiftCommandState,
            buildOptions: self.buildCommandOptions,
            destinationAbsolutePath: destinationPath,
            testingFolderName: decisionPath,
            argumentPath: args,
            initialPackageType: self.initialPackageType,
            cwd: self.cwd,
            buildSystem: self.buildSystem
        )
    }

    /// Generates and builds a template in a specific directory with given arguments.
    ///
    /// - Parameters:
    ///   - commandPlugin: The resolved plugin module to execute.
    ///   - swiftCommandState: The Swift command state for build configuration and observability.
    ///   - buildOptions: Options to use when building the template.
    ///   - destinationAbsolutePath: Directory where the template will be generated.
    ///   - testingFolderName: Name of the folder corresponding to this test branch.
    ///   - argumentPath: Command-line arguments for the template plugin.
    ///   - initialPackageType: The package type to use for initializing the template.
    ///   - cwd: Current working directory.
    ///   - buildSystem: The build system provider to use for compiling the template.
    /// - Returns: `TestTemplateInfo` containing durations, success flags, and optional log file path.
    /// - Throws: Any error encountered during template generation, plugin execution, or build.
    private func testTemplateInitialization(
        commandPlugin: ResolvedModule,
        swiftCommandState: SwiftCommandState,
        buildOptions: BuildCommandOptions,
        destinationAbsolutePath: AbsolutePath,
        testingFolderName: String,
        argumentPath: [String],
        initialPackageType: InitPackage.PackageType,
        cwd: AbsolutePath,
        buildSystem: BuildSystemProvider.Kind
    ) async throws -> TestTemplateResult {
        let startGen = DispatchTime.now()
        var genSuccess = false
        var buildSuccess = false
        var genDuration: DispatchTimeInterval = .never
        var buildDuration: DispatchTimeInterval = .never
        var logPath: String? = nil

        swiftCommandState.observabilityScope
            .emit(debug: "Generating \(testingFolderName) with arguments \(argumentPath)")
        do {
            let log = destinationAbsolutePath.appending("generation-output.log").pathString
            let (origOut, origErr) = try redirectStdoutAndStderr(to: log)
            defer { restoreStdoutAndStderr(originalStdout: origOut, originalStderr: origErr) }

            let initTemplate = try InitTemplatePackage(
                name: testingFolderName,
                initMode: .fileSystem(.init(path: cwd.pathString)),
                fileSystem: swiftCommandState.fileSystem,
                packageType: initialPackageType,
                supportedTestingLibraries: [],
                destinationPath: destinationAbsolutePath,
                installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
            )

            try initTemplate.setupTemplateManifest()

            let graph = try await swiftCommandState
                .withTemporaryWorkspace(switchingTo: destinationAbsolutePath) { _, _ in
                    try await swiftCommandState.loadPackageGraph()
                }

            try await TemplateBuildSupport.buildForTesting(
                swiftCommandState: swiftCommandState,
                buildOptions: buildOptions,
                testingFolder: destinationAbsolutePath
            )

            try await swiftCommandState.withTemporaryWorkspace(switchingTo: destinationAbsolutePath) { _, _ in
                let output = try await TemplatePluginExecutor.execute(
                    plugin: commandPlugin,
                    rootPackage: graph.rootPackages.first!,
                    packageGraph: graph,
                    buildSystemKind: buildSystem,
                    arguments: argumentPath,
                    swiftCommandState: swiftCommandState,
                    requestPermission: false
                )
                guard let pluginOutput = String(data: output, encoding: .utf8) else {
                    throw TestTemplateCommandError.invalidUTF8Encoding(output)
                }
                print(pluginOutput)
            }

            genDuration = startGen.distance(to: .now())
            genSuccess = true
            try FileManager.default.removeItem(atPath: log)
        } catch {
            genDuration = startGen.distance(to: .now())
            genSuccess = false

            let generationError = TestTemplateCommandError.generationFailed(error.localizedDescription)
            swiftCommandState.observabilityScope.emit(generationError)

            let errorLog = destinationAbsolutePath.appending("generation-output.log")
            logPath = try? self.captureAndWriteError(
                to: errorLog,
                error: error,
                context: "Plugin Output (before failure)"
            )
        }

        if genSuccess {
            let buildStart = DispatchTime.now()
            do {
                let log = destinationAbsolutePath.appending("build-output.log").pathString
                let (origOut, origErr) = try redirectStdoutAndStderr(to: log)
                defer { restoreStdoutAndStderr(originalStdout: origOut, originalStderr: origErr) }

                try await TemplateBuildSupport.buildForTesting(
                    swiftCommandState: swiftCommandState,
                    buildOptions: buildOptions,
                    testingFolder: destinationAbsolutePath
                )

                buildDuration = buildStart.distance(to: .now())
                buildSuccess = true
                try FileManager.default.removeItem(atPath: log)
            } catch {
                buildDuration = buildStart.distance(to: .now())
                buildSuccess = false

                let buildError = TestTemplateCommandError.buildFailed(error.localizedDescription)
                swiftCommandState.observabilityScope.emit(buildError)

                let errorLog = destinationAbsolutePath.appending("build-output.log")
                logPath = try? self.captureAndWriteError(
                    to: errorLog,
                    error: error,
                    context: "Build Output (before failure)"
                )
            }
        }

        return TestTemplateResult(
            generationDuration: genDuration,
            buildDuration: buildDuration,
            generationSuccess: genSuccess,
            buildSuccess: buildSuccess,
            logFilePath: logPath
        )
    }

    private func redirectStdoutAndStderr(to path: String) throws -> (originalStdout: Int32, originalStderr: Int32) {
        #if os(Windows)
        guard let file = _fsopen(path, "w", _SH_DENYWR) else {
            throw TestTemplateCommandError.outputRedirectionFailed(path)
        }
        let originalStdout = _dup(_fileno(stdout))
        let originalStderr = _dup(_fileno(stderr))
        _dup2(_fileno(file), _fileno(stdout))
        _dup2(_fileno(file), _fileno(stderr))
        fclose(file)
        return (originalStdout, originalStderr)
        #else
        guard let file = fopen(path, "w") else {
            throw TestTemplateCommandError.outputRedirectionFailed(path)
        }
        let originalStdout = dup(STDOUT_FILENO)
        let originalStderr = dup(STDERR_FILENO)
        dup2(fileno(file), STDOUT_FILENO)
        dup2(fileno(file), STDERR_FILENO)
        fclose(file)
        return (originalStdout, originalStderr)
        #endif
    }

    private func restoreStdoutAndStderr(originalStdout: Int32, originalStderr: Int32) {
        fflush(stdout)
        fflush(stderr)
        #if os(Windows)
        _dup2(originalStdout, _fileno(stdout))
        _dup2(originalStderr, _fileno(stderr))
        _close(originalStdout)
        _close(originalStderr)
        #else
        dup2(originalStdout, STDOUT_FILENO)
        dup2(originalStderr, STDERR_FILENO)
        close(originalStdout)
        close(originalStderr)
        #endif
    }

    private func captureAndWriteError(to path: AbsolutePath, error: Error, context: String) throws -> String {
        let existingOutput = (try? String(contentsOf: path.asURL)) ?? ""
        let logContent =
            """
            Error:
            --------------------------------
            \(error.localizedDescription)

            \(context):
            --------------------------------
            \(existingOutput)
            """
        try logContent.write(to: path.asURL, atomically: true, encoding: .utf8)
        return path.pathString
    }
}

extension String {
    private func padded(_ toLength: Int) -> String {
        self.padding(toLength: toLength, withPad: " ", startingAt: 0)
    }
}

extension TestTemplateResult {
    // MARK: Utility functions to print TestTemplateInfo matrix

    static func printBuildMatrix(_ matrix: [String: TestTemplateResult]) {
        let header = [
            "Argument Branch".padding(toLength: 30, withPad: " ", startingAt: 0),
            "Gen Success".padding(toLength: 12, withPad: " ", startingAt: 0),
            "Gen Time(s)".padding(toLength: 12, withPad: " ", startingAt: 0),
            "Build Success".padding(toLength: 14, withPad: " ", startingAt: 0),
            "Build Time(s)".padding(toLength: 14, withPad: " ", startingAt: 0),
            "Log File",
        ]
        print(header.joined(separator: " "))

        for (folder, info) in matrix {
            let row = [
                folder.padding(toLength: 30, withPad: " ", startingAt: 0),
                String(info.generationSuccess).padding(toLength: 12, withPad: " ", startingAt: 0),
                String(format: "%.2f", info.generationDuration.seconds).padding(
                    toLength: 12,
                    withPad: " ",
                    startingAt: 0
                ),
                String(info.buildSuccess).padding(toLength: 14, withPad: " ", startingAt: 0),
                String(format: "%.2f", info.buildDuration.seconds).padding(
                    toLength: 14,
                    withPad: " ",
                    startingAt: 0
                ),
                info.logFilePath ?? "-",
            ]
            print(row.joined(separator: " "))
        }
    }

    static func printJSONMatrix(_ matrix: [String: TestTemplateResult]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(matrix)
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            } else {
                print("Failed to convert JSON data to string")
            }
        } catch {
            print("Failed to encode JSON: \(error.localizedDescription)")
        }
    }
}
