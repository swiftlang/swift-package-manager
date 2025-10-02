import ArgumentParser
import ArgumentParserToolInfo

@_spi(SwiftPMInternal)
import Basics

import _Concurrency

@_spi(SwiftPMInternal)
import CoreCommands

import Dispatch
import Foundation
import PackageGraph
@_spi(PackageRefactor) import SwiftRefactor
@_spi(SwiftPMInternal)
import PackageModel

import SPMBuildCore
import TSCUtility

import func TSCLibc.exit
import Workspace

import class Basics.AsyncProcess
import struct TSCBasic.ByteString
import struct TSCBasic.FileSystemError
import enum TSCBasic.JSON
import var TSCBasic.stdoutStream
import class TSCBasic.SynchronizedQueue
import class TSCBasic.Thread

extension DispatchTimeInterval {
    var seconds: TimeInterval {
        switch self {
        case .seconds(let s): return TimeInterval(s)
        case .milliseconds(let ms): return TimeInterval(Double(ms) / 1000)
        case .microseconds(let us): return TimeInterval(Double(us) / 1_000_000)
        case .nanoseconds(let ns): return TimeInterval(Double(ns) / 1_000_000_000)
        case .never: return 0
        @unknown default: return 0
        }
    }
}

extension SwiftTestCommand {
    /// Test the various outputs of a template.
    struct Template: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Test the various outputs of a template"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var sharedOptions: SharedOptions

        /// Specify name of the template.
        @Option(help: "Specify name of the template")
        var templateName: String?

        /// Specify the output path of the created templates.
        @Option(
            name: .customLong("output-path"),
            help: "Specify the output path of the created templates.",
            completion: .directory
        )
        var outputDirectory: AbsolutePath

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

        /// Predetermined arguments specified by the consumer.
        @Argument(
            help: "Predetermined arguments to pass for testing template."
        )
        var args: [String] = []

        /// Specify the branch of the template you want to test.
        @Option(
            name: .customLong("branches"),
            parsing: .upToNextOption,
            help: "Specify the branch of the template you want to test. Format: --branches branch1 branch2",
        )
        var branches: [String] = []

        /// Dry-run to display argument tree.
        @Flag(help: "Dry-run to display argument tree")
        var dryRun: Bool = false

        /// Output format for the templates result.
        ///
        /// Can be either `.matrix` (default) or `.json`.
        @Option(help: "Set the output format.")
        var format: ShowTestTemplateOutput = .matrix

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            do {
                let directoryManager = TemplateTestingDirectoryManager(
                    fileSystem: swiftCommandState.fileSystem,
                    observabilityScope: swiftCommandState.observabilityScope
                )
                try directoryManager.createOutputDirectory(
                    outputDirectoryPath: self.outputDirectory,
                    swiftCommandState: swiftCommandState
                )

                let buildSystem = self.globalOptions.build.buildSystem != .native ?
                    self.globalOptions.build.buildSystem :
                    swiftCommandState.options.build.buildSystem

                let resolvedTemplateName: String = if self.templateName == nil {
                    try await self.findTemplateName(from: cwd, swiftCommandState: swiftCommandState)
                } else {
                    self.templateName!
                }

                let pluginManager = try await TemplateTesterPluginManager(
                    swiftCommandState: swiftCommandState,
                    template: resolvedTemplateName,
                    scratchDirectory: cwd,
                    args: args,
                    branches: branches,
                    buildSystem: buildSystem,
                )

                let commandPlugin: ResolvedModule = try pluginManager.loadTemplatePlugin()

                let commandLineFragments: [CommandPath] = try await pluginManager.run()

                if self.dryRun {
                    for commandLine in commandLineFragments {
                        print(commandLine.displayFormat())
                    }
                    return
                }
                let packageType = try await inferPackageType(swiftCommandState: swiftCommandState, from: cwd)

                var buildMatrix: [String: BuildInfo] = [:]

                for commandLine in commandLineFragments {
                    let folderName = commandLine.fullPathKey

                    buildMatrix[folderName] = try await self.testDecisionTreeBranch(
                        folderName: folderName,
                        commandLine: commandLine.commandChain,
                        swiftCommandState: swiftCommandState,
                        packageType: packageType,
                        commandPlugin: commandPlugin,
                        cwd: cwd,
                        buildSystem: buildSystem
                    )
                }

                switch self.format {
                case .matrix:
                    self.printBuildMatrix(buildMatrix)
                case .json:
                    self.printJSONMatrix(buildMatrix)
                }
            } catch {
                swiftCommandState.observabilityScope.emit(error)
            }
        }

        private func testDecisionTreeBranch(
            folderName: String,
            commandLine: [CommandComponent],
            swiftCommandState: SwiftCommandState,
            packageType: InitPackage.PackageType,
            commandPlugin: ResolvedModule,
            cwd: AbsolutePath,
            buildSystem: BuildSystemProvider.Kind
        ) async throws -> BuildInfo {
            let destinationPath = self.outputDirectory.appending(component: folderName)

            swiftCommandState.observabilityScope.emit(debug: "Generating \(folderName)")
            do {
                try FileManager.default.createDirectory(at: destinationPath.asURL, withIntermediateDirectories: true)
            } catch {
                throw TestTemplateCommandError.directoryCreationFailed(destinationPath.pathString)
            }

            return try await self.testTemplateInitialization(
                commandPlugin: commandPlugin,
                swiftCommandState: swiftCommandState,
                buildOptions: self.buildOptions,
                destinationAbsolutePath: destinationPath,
                testingFolderName: folderName,
                argumentPath: commandLine,
                initialPackageType: packageType,
                cwd: cwd,
                buildSystem: buildSystem
            )
        }

        private func printBuildMatrix(_ matrix: [String: BuildInfo]) {
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

        private func printJSONMatrix(_ matrix: [String: BuildInfo]) {
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

        private func inferPackageType(
            swiftCommandState: SwiftCommandState,
            from templatePath: Basics.AbsolutePath
        ) async throws -> InitPackage.PackageType {
            let workspace = try swiftCommandState.getActiveWorkspace()
            let root = try swiftCommandState.getWorkspaceRoot()

            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftCommandState.observabilityScope
            )

            guard let manifest = rootManifests.values.first else {
                throw TestTemplateCommandError.invalidManifestInTemplate
            }

            var targetName = self.templateName

            if targetName == nil {
                targetName = try self.findTemplateName(from: manifest)
            }

            for target in manifest.targets {
                if target.name == targetName,
                   let options = target.templateInitializationOptions,
                   case .packageInit(let type, _, _) = options
                {
                    return try .init(from: type)
                }
            }

            throw TestTemplateCommandError.templateNotFound(targetName ?? "<unspecified>")
        }

        private func findTemplateName(from manifest: Manifest) throws -> String {
            let templateTargets = manifest.targets.compactMap { target -> String? in
                if let options = target.templateInitializationOptions,
                   case .packageInit = options
                {
                    return target.name
                }
                return nil
            }

            switch templateTargets.count {
            case 0:
                throw TestTemplateCommandError.noTemplatesInManifest
            case 1:
                return templateTargets[0]
            default:
                throw TestTemplateCommandError.multipleTemplatesFound(templateTargets)
            }
        }

        func findTemplateName(
            from templatePath: Basics.AbsolutePath,
            swiftCommandState: SwiftCommandState
        ) async throws -> String {
            try await swiftCommandState.withTemporaryWorkspace(switchingTo: templatePath) { workspace, root in
                let rootManifests = try await workspace.loadRootManifests(
                    packages: root.packages,
                    observabilityScope: swiftCommandState.observabilityScope
                )

                guard let manifest = rootManifests.values.first else {
                    throw TestTemplateCommandError.invalidManifestInTemplate
                }

                return try self.findTemplateName(from: manifest)
            }
        }

        private func testTemplateInitialization(
            commandPlugin: ResolvedModule,
            swiftCommandState: SwiftCommandState,
            buildOptions: BuildCommandOptions,
            destinationAbsolutePath: AbsolutePath,
            testingFolderName: String,
            argumentPath: [CommandComponent],
            initialPackageType: InitPackage.PackageType,
            cwd: AbsolutePath,
            buildSystem: BuildSystemProvider.Kind
        ) async throws -> BuildInfo {
            let startGen = DispatchTime.now()
            var genSuccess = false
            var buildSuccess = false
            var genDuration: DispatchTimeInterval = .never
            var buildDuration: DispatchTimeInterval = .never
            var logPath: String? = nil

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

                // Build flat command with all subcommands and arguments
                let flatCommand = self.buildFlatCommand(from: argumentPath)

                print("Running plugin with args:", flatCommand)

                try await swiftCommandState.withTemporaryWorkspace(switchingTo: destinationAbsolutePath) { _, _ in
                    let output = try await TemplatePluginExecutor.execute(
                        plugin: commandPlugin,
                        rootPackage: graph.rootPackages.first!,
                        packageGraph: graph,
                        buildSystemKind: buildSystem,
                        arguments: flatCommand,
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

            // Build step
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

            return BuildInfo(
                generationDuration: genDuration,
                buildDuration: buildDuration,
                generationSuccess: genSuccess,
                buildSuccess: buildSuccess,
                logFilePath: logPath
            )
        }

        private func buildFlatCommand(from argumentPath: [CommandComponent]) -> [String] {
            var result: [String] = []

            for (index, command) in argumentPath.enumerated() {
                if index > 0 {
                    result.append(command.commandName)
                }
                let commandArgs = command.arguments.flatMap(\.commandLineFragments)
                result.append(contentsOf: commandArgs)
            }

            return result
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

        enum ShowTestTemplateOutput: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument,
            CaseIterable
        {
            case matrix
            case json

            var description: String { rawValue }
        }

        struct BuildInfo: Encodable {
            var generationDuration: DispatchTimeInterval
            var buildDuration: DispatchTimeInterval
            var generationSuccess: Bool
            var buildSuccess: Bool
            var logFilePath: String?

            enum CodingKeys: String, CodingKey {
                case generationDuration, buildDuration, generationSuccess, buildSuccess, logFilePath
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(self.generationDuration.seconds, forKey: .generationDuration)
                try container.encode(self.buildDuration.seconds, forKey: .buildDuration)
                try container.encode(self.generationSuccess, forKey: .generationSuccess)
                try container.encode(self.buildSuccess, forKey: .buildSuccess)
                try container.encodeIfPresent(self.logFilePath, forKey: .logFilePath)
            }
        }

        enum TestTemplateCommandError: Error, CustomStringConvertible {
            case invalidManifestInTemplate
            case templateNotFound(String)
            case noTemplatesInManifest
            case multipleTemplatesFound([String])
            case directoryCreationFailed(String)
            case buildSystemNotSupported(String)
            case generationFailed(String)
            case buildFailed(String)
            case outputRedirectionFailed(String)
            case invalidUTF8Encoding(Data)

            var description: String {
                switch self {
                case .invalidManifestInTemplate:
                    "Invalid or missing Package.swift manifest found in template. The template must contain a valid Swift package manifest."
                case .templateNotFound(let templateName):
                    "Could not find template '\(templateName)' with packageInit options. Verify the template name and ensure it has proper template configuration."
                case .noTemplatesInManifest:
                    "No templates with packageInit options were found in the manifest. The package must contain at least one target with template initialization options."
                case .multipleTemplatesFound(let templates):
                    "Multiple templates found: \(templates.joined(separator: ", ")). Please specify one using --template-name option."
                case .directoryCreationFailed(let path):
                    "Failed to create output directory at '\(path)'. Check permissions and available disk space."
                case .buildSystemNotSupported(let system):
                    "Build system '\(system)' is not supported for template testing. Use a supported build system."
                case .generationFailed(let details):
                    "Template generation failed: \(details). Check template configuration and input arguments."
                case .buildFailed(let details):
                    "Build failed after template generation: \(details). Check generated code and dependencies."
                case .outputRedirectionFailed(let path):
                    "Failed to redirect output to log file at '\(path)'. Check file permissions and disk space."
                case .invalidUTF8Encoding(let data):
                    "Failed to encode \(data) into UTF-8."
                }
            }
        }
    }
}

extension String {
    private func padded(_ toLength: Int) -> String {
        self.padding(toLength: toLength, withPad: " ", startingAt: 0)
    }
}
