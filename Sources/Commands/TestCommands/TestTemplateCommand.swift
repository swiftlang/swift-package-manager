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


//DEAL WITH THIS LATER
public struct TemplateTestingDirectoryManager {
    let fileSystem: FileSystem

    //revisit
    func createTemporaryDirectories(directories: Set<String>) throws -> [Basics.AbsolutePath] {

        var result: [Basics.AbsolutePath] = []
        for directory in directories {
            let dirPath = try fileSystem.tempDirectory.appending(component: directory)
            try fileSystem.createDirectory(dirPath)
            result.append(dirPath)
        }

        return result
    }

    func createOutputDirectory(outputDirectoryPath: Basics.AbsolutePath, swiftCommandState: SwiftCommandState) throws {
        let manifest = outputDirectoryPath.appending(component: Manifest.filename)
        let fileSystem = swiftCommandState.fileSystem
        let directoryExists = fileSystem.exists(outputDirectoryPath)

        if !directoryExists {
            try FileManager.default.createDirectory(
                at: outputDirectoryPath.asURL,
                withIntermediateDirectories: true
            )
        } else {
            if fileSystem.exists(manifest) {
                throw ValidationError("Package.swift was found in \(outputDirectoryPath).")
            }
        }

    }
}


extension SwiftTestCommand {
    struct Template: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Test the various outputs of a template"
        )

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var sharedOptions: SharedOptions

        @Option(help: "Specify name of the template")
        var templateName: String?

        @Option(
            name: .customLong("output-path"),
            help: "Specify the output path of the created templates.",
            completion: .directory
        )
        public var outputDirectory: AbsolutePath

        @OptionGroup(visibility: .hidden)
        var buildOptions: BuildCommandOptions

        /// Predetermined arguments specified by the consumer.
        @Argument(
            help: "Predetermined arguments to pass to the template."
        )
        var args: [String] = []

        @Flag(help: "Dry-run to display argument tree")
        var dryRun: Bool = false

        /// Output format for the templates result.
        ///
        /// Can be either `.matrix` (default) or `.json`.
        @Option(help: "Set the output format.")
        var format: ShowTestTemplateOutput = .matrix


        func run(_ swiftCommandState: SwiftCommandState) async throws {

            guard let cwd = swiftCommandState.fileSystem.currentWorkingDirectory else {
                throw ValidationError("Could not determine current working directory.")
            }

            let directoryManager = TemplateTestingDirectoryManager(fileSystem: swiftCommandState.fileSystem)
            try directoryManager.createOutputDirectory(outputDirectoryPath: outputDirectory, swiftCommandState: swiftCommandState)

            let pluginManager = try await TemplateTesterPluginManager(
                swiftCommandState: swiftCommandState,
                template: templateName,
                scratchDirectory: cwd,
                args: args
            )

            let commandPlugin = try pluginManager.loadTemplatePlugin()
            let commandLineFragments = try await pluginManager.run()
            let packageType = try await inferPackageType(swiftCommandState: swiftCommandState, from: cwd)


            var buildMatrix: [String: BuildInfo] = [:]

            for commandLine in commandLineFragments {

                let folderName = commandLine.fullPathKey

                buildMatrix[folderName] = try await testDecisionTreeBranch(folderName: folderName, commandLine: commandLine, swiftCommandState: swiftCommandState, packageType: packageType, commandPlugin: commandPlugin)

            }

            switch self.format {
            case .matrix:
                printBuildMatrix(buildMatrix)
            case .json:
                printJSONMatrix(buildMatrix)
            }
        }

        private func testDecisionTreeBranch(folderName: String, commandLine: CommandPath, swiftCommandState: SwiftCommandState, packageType: InitPackage.PackageType, commandPlugin: ResolvedModule) async throws -> BuildInfo {
            let destinationPath = outputDirectory.appending(component: folderName)

            swiftCommandState.observabilityScope.emit(debug: "Generating \(folderName)")
            try FileManager.default.createDirectory(at: destinationPath.asURL, withIntermediateDirectories: true)

            return try await testTemplateInitialization(
                commandPlugin: commandPlugin,
                swiftCommandState: swiftCommandState,
                buildOptions: buildOptions,
                destinationAbsolutePath: destinationPath,
                testingFolderName: folderName,
                argumentPath: commandLine,
                initialPackageType: packageType
            )
        }

        private func printBuildMatrix(_ matrix: [String: BuildInfo]) {
            let header = [
                "Argument Branch".padding(toLength: 30, withPad: " ", startingAt: 0),
                "Gen Success".padding(toLength: 12, withPad: " ", startingAt: 0),
                "Gen Time(s)".padding(toLength: 12, withPad: " ", startingAt: 0),
                "Build Success".padding(toLength: 14, withPad: " ", startingAt: 0),
                "Build Time(s)".padding(toLength: 14, withPad: " ", startingAt: 0),
                "Log File"
            ]
            print(header.joined(separator: " "))

            for (folder, info) in matrix {
                let row = [
                    folder.padding(toLength: 30, withPad: " ", startingAt: 0),
                    String(info.generationSuccess).padding(toLength: 12, withPad: " ", startingAt: 0),
                    String(format: "%.2f", info.generationDuration.seconds).padding(toLength: 12, withPad: " ", startingAt: 0),
                    String(info.buildSuccess).padding(toLength: 14, withPad: " ", startingAt: 0),
                    String(format: "%.2f", info.buildDuration.seconds).padding(toLength: 14, withPad: " ", startingAt: 0),
                    info.logFilePath ?? "-"
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
                }
            } catch {
                print("Failed to encode JSON: \(error)")
            }

        }

        private func inferPackageType(swiftCommandState: SwiftCommandState, from templatePath: Basics.AbsolutePath) async throws -> InitPackage.PackageType {
            let workspace = try swiftCommandState.getActiveWorkspace()
            let root = try swiftCommandState.getWorkspaceRoot()

            let rootManifests = try await workspace.loadRootManifests(
                packages: root.packages,
                observabilityScope: swiftCommandState.observabilityScope
            )

            guard let manifest = rootManifests.values.first else {
                throw ValidationError("")
            }

            var targetName = templateName

            if targetName == nil {
                targetName = try findTemplateName(from: manifest)
            }

            for target in manifest.targets {
                if target.name == targetName,
                   let options = target.templateInitializationOptions,
                   case .packageInit(let type, _, _) = options {
                    return try .init(from: type)
                }
            }

            throw ValidationError("")
        }


        private func findTemplateName(from manifest: Manifest) throws -> String {
            let templateTargets = manifest.targets.compactMap { target -> String? in
                if let options = target.templateInitializationOptions,
                   case .packageInit = options {
                    return target.name
                }
                return nil
            }

            switch templateTargets.count {
            case 0:
                throw ValidationError("")
            case 1:
                return templateTargets[0]
            default:
                throw ValidationError("")
            }
        }


        private func testTemplateInitialization(
            commandPlugin: ResolvedModule,
            swiftCommandState: SwiftCommandState,
            buildOptions: BuildCommandOptions,
            destinationAbsolutePath: AbsolutePath,
            testingFolderName: String,
            argumentPath: CommandPath,
            initialPackageType: InitPackage.PackageType
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
                    initMode: .fileSystem(name: templateName, path: swiftCommandState.originalWorkingDirectory.pathString),
                    templatePath: swiftCommandState.originalWorkingDirectory,
                    fileSystem: swiftCommandState.fileSystem,
                    packageType: initialPackageType,
                    supportedTestingLibraries: [],
                    destinationPath: destinationAbsolutePath,
                    installedSwiftPMConfiguration: swiftCommandState.getHostToolchain().installedSwiftPMConfiguration
                )

                try initTemplate.setupTemplateManifest()

                let graph = try await swiftCommandState.withTemporaryWorkspace(switchingTo: destinationAbsolutePath) { _, _ in
                    try await swiftCommandState.loadPackageGraph()
                }

                for (index, command) in argumentPath.commandChain.enumerated() {
                    let commandArgs = command.arguments.flatMap { $0.commandLineFragments }
                    let fullCommand = (index == 0) ? [] : Array(argumentPath.commandChain.prefix(index + 1).map(\.commandName)) + commandArgs

                    print("Running plugin with args:", fullCommand)

                    try await swiftCommandState.withTemporaryWorkspace(switchingTo: destinationAbsolutePath) { _, _ in
                        _ = try await TemplatePluginRunner.run(
                            plugin: commandPlugin,
                            package: graph.rootPackages.first!,
                            packageGraph: graph,
                            arguments: fullCommand,
                            swiftCommandState: swiftCommandState
                        )
                    }
                }

                genDuration = startGen.distance(to: .now())
                genSuccess = true
                try FileManager.default.removeItem(atPath: log)
            } catch {
                genDuration = startGen.distance(to: .now())
                genSuccess = false

                let errorLog = destinationAbsolutePath.appending("generation-output.log")
                logPath = try? captureAndWriteError(
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

                    let errorLog = destinationAbsolutePath.appending("build-output.log")
                    logPath = try? captureAndWriteError(
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
            guard let file = fopen(path, "w") else {
                throw NSError(domain: "RedirectError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open file for writing"])
            }

            let originalStdout = dup(STDOUT_FILENO)
            let originalStderr = dup(STDERR_FILENO)
            dup2(fileno(file), STDOUT_FILENO)
            dup2(fileno(file), STDERR_FILENO)
            fclose(file)
            return (originalStdout, originalStderr)
        }

        private func restoreStdoutAndStderr(originalStdout: Int32, originalStderr: Int32) {
            fflush(stdout)
            fflush(stderr)

            dup2(originalStdout, STDOUT_FILENO)
            dup2(originalStderr, STDERR_FILENO)
            close(originalStdout)
            close(originalStderr)
        }

        enum ShowTestTemplateOutput: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument, CaseIterable {
            case matrix
            case json

            public var description: String { rawValue }
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
                try container.encode(generationDuration.seconds, forKey: .generationDuration)
                try container.encode(buildDuration.seconds, forKey: .buildDuration)
                try container.encode(generationSuccess, forKey: .generationSuccess)
                try container.encode(buildSuccess, forKey: .buildSuccess)
                try container.encodeIfPresent(logFilePath, forKey: .logFilePath)
            }
        }
    }
}

private extension String {
    func padded(_ toLength: Int) -> String {
        self.padding(toLength: toLength, withPad: " ", startingAt: 0)
    }
}

