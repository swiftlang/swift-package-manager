//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct Basics.AbsolutePath
import struct Basics.Diagnostic
import typealias Basics.EnvironmentVariables
import protocol Basics.FileSystem
import struct Basics.ObservabilityMetadata
import class Basics.ObservabilityScope
import enum Basics.SandboxNetworkPermission
import struct Basics.StringError
import struct Foundation.Data
import struct PackageModel.BuildEnvironment
import class PackageModel.PluginTarget

extension PluginTarget {
    public func invoke(
        action: PluginAction,
        buildEnvironment: BuildEnvironment,
        scriptRunner: PluginScriptRunner,
        workingDirectory: AbsolutePath,
        outputDirectory: AbsolutePath,
        toolSearchDirectories: [AbsolutePath],
        accessibleTools: [String: (path: AbsolutePath, triples: [String]?)],
        writableDirectories: [AbsolutePath],
        readOnlyDirectories: [AbsolutePath],
        allowNetworkConnections: [SandboxNetworkPermission],
        pkgConfigDirectories: [AbsolutePath],
        sdkRootPath: AbsolutePath?,
        fileSystem: any FileSystem,
        observabilityScope: ObservabilityScope,
        delegate: AsyncPluginInvocationDelegate
    ) async throws -> Bool {
        // Create the plugin's output directory if needed (but don't do anything with it if it already exists).
        do {
            try fileSystem.createDirectory(outputDirectory, recursive: true)
        } catch {
            throw PluginEvaluationError.couldNotCreateOutputDirectory(path: outputDirectory, underlyingError: error)
        }

        // Serialize the plugin action to send as the initial message.
        let initialMessage: Data
        do {
            var serializer = PluginContextSerializer(
                fileSystem: fileSystem,
                buildEnvironment: buildEnvironment,
                pkgConfigDirectories: pkgConfigDirectories,
                sdkRootPath: sdkRootPath
            )
            let pluginWorkDirId = try serializer.serialize(path: outputDirectory)
            let toolSearchDirIds = try toolSearchDirectories.map{ try serializer.serialize(path: $0) }
            let accessibleTools = try accessibleTools.mapValues { (tool: (AbsolutePath, [String]?)) -> HostToPluginMessage.InputContext.Tool in
                let path = try serializer.serialize(path: tool.0)
                return .init(path: path, triples: tool.1)
            }
            let actionMessage: HostToPluginMessage
            switch action {

            case .createBuildToolCommands(let package, let target, let pluginGeneratedSources, let pluginGeneratedResources):
                let rootPackageId = try serializer.serialize(package: package)
                guard let targetId = try serializer.serialize(target: target) else {
                    throw StringError("unexpectedly was unable to serialize target \(target)")
                }
                let generatedSources = try pluginGeneratedSources.map { try serializer.serialize(path: $0) }
                let generatedResources = try pluginGeneratedResources.map { try serializer.serialize(path: $0) }
                let wireInput = WireInput(
                    paths: serializer.paths,
                    targets: serializer.targets,
                    products: serializer.products,
                    packages: serializer.packages,
                    pluginWorkDirId: pluginWorkDirId,
                    toolSearchDirIds: toolSearchDirIds,
                    accessibleTools: accessibleTools)
                actionMessage = .createBuildToolCommands(
                    context: wireInput,
                    rootPackageId: rootPackageId,
                    targetId: targetId,
                    pluginGeneratedSources: generatedSources,
                    pluginGeneratedResources: generatedResources
                )
            case .performCommand(let package, let arguments):
                let rootPackageId = try serializer.serialize(package: package)
                let wireInput = WireInput(
                    paths: serializer.paths,
                    targets: serializer.targets,
                    products: serializer.products,
                    packages: serializer.packages,
                    pluginWorkDirId: pluginWorkDirId,
                    toolSearchDirIds: toolSearchDirIds,
                    accessibleTools: accessibleTools)
                actionMessage = .performCommand(
                    context: wireInput,
                    rootPackageId: rootPackageId,
                    arguments: arguments)
            }
            initialMessage = try actionMessage.toData()
        } catch {
            throw PluginEvaluationError.couldNotSerializePluginInput(underlyingError: error)
        }

        // Handle messages and output from the plugin.
        class ScriptRunnerDelegate: PluginScriptCompilerDelegate, PluginScriptRunnerDelegate {
            /// Delegate that should be told about events involving the plugin.
            let invocationDelegate: PluginInvocationDelegate

            /// Observability scope for the invoking of the plugin. Diagnostics from the plugin itself are sent through the delegate.
            let observabilityScope: ObservabilityScope

            /// Whether at least one error has been reported; this is used to make sure there is at least one error if the plugin fails.
            var hasReportedError = false

            /// If this is true, we exited early with an error.
            var exitEarly = false

            init(invocationDelegate: PluginInvocationDelegate, observabilityScope: ObservabilityScope) {
                self.invocationDelegate = invocationDelegate
                self.observabilityScope = observabilityScope
            }

            func willCompilePlugin(commandLine: [String], environment: EnvironmentVariables) {
                invocationDelegate.pluginCompilationStarted(commandLine: commandLine, environment: environment)
            }

            func didCompilePlugin(result: PluginCompilationResult) {
                invocationDelegate.pluginCompilationEnded(result: result)
            }

            func skippedCompilingPlugin(cachedResult: PluginCompilationResult) {
                invocationDelegate.pluginCompilationWasSkipped(cachedResult: cachedResult)
            }

            /// Invoked when the plugin emits arbitrary data on its stdout/stderr. There is no guarantee that the data is split on UTF-8 character encoding boundaries etc.  The script runner delegate just passes it on to the invocation delegate.
            func handleOutput(data: Data) {
                invocationDelegate.pluginEmittedOutput(data)
            }

            /// Invoked when the plugin emits a message. The `responder` closure can be used to send any reply messages.
            func handleMessage(data: Data, responder: @escaping (Data) -> Void) throws {
                let message = try PluginToHostMessage(data)
                switch message {

                case .emitDiagnostic(let severity, let message, let file, let line):
                    let metadata: ObservabilityMetadata? = file.map {
                        var metadata = ObservabilityMetadata()
                        // FIXME: We should probably report some kind of protocol error if the path isn't valid.
                        metadata.fileLocation = try? .init(.init(validating: $0), line: line)
                        return metadata
                    }
                    let diagnostic: Basics.Diagnostic
                    switch severity {
                    case .error:
                        diagnostic = .error(message, metadata: metadata)
                        hasReportedError = true
                    case .warning:
                        diagnostic = .warning(message, metadata: metadata)
                    case .remark:
                        diagnostic = .info(message, metadata: metadata)
                    }
                    self.invocationDelegate.pluginEmittedDiagnostic(diagnostic)

                case .emitProgress(let message):
                    self.invocationDelegate.pluginEmittedProgress(message)

                case .defineBuildCommand(let config, let inputFiles, let outputFiles):
                    if config.version != 2 {
                        throw PluginEvaluationError.pluginUsesIncompatibleVersion(expected: 2, actual: config.version)
                    }
                    self.invocationDelegate.pluginDefinedBuildCommand(
                        displayName: config.displayName,
                        executable: try AbsolutePath(validating: config.executable.path),
                        arguments: config.arguments,
                        environment: config.environment,
                        workingDirectory: try config.workingDirectory.map{ try AbsolutePath(validating: $0.path) },
                        inputFiles: try inputFiles.map{ try AbsolutePath(validating: $0.path) },
                        outputFiles: try outputFiles.map{ try AbsolutePath(validating: $0.path) })

                case .definePrebuildCommand(let config, let outputFilesDir):
                    if config.version != 2 {
                        throw PluginEvaluationError.pluginUsesIncompatibleVersion(expected: 2, actual: config.version)
                    }
                    let success = self.invocationDelegate.pluginDefinedPrebuildCommand(
                        displayName: config.displayName,
                        executable: try AbsolutePath(validating: config.executable.path),
                        arguments: config.arguments,
                        environment: config.environment,
                        workingDirectory: try config.workingDirectory.map{ try AbsolutePath(validating: $0.path) },
                        outputFilesDirectory: try AbsolutePath(validating: outputFilesDir.path))

                    if !success {
                        exitEarly = true
                        hasReportedError = true
                    }

                case .buildOperationRequest(let subset, let parameters):
                    self.invocationDelegate.pluginRequestedBuildOperation(subset: .init(subset), parameters: .init(parameters)) {
                        do {
                            switch $0 {
                            case .success(let result):
                                responder(try HostToPluginMessage.buildOperationResponse(result: .init(result)).toData())
                            case .failure(let error):
                                responder(try HostToPluginMessage.errorResponse(error: String(describing: error)).toData())
                            }
                        }
                        catch {
                            self.observabilityScope.emit(debug: "couldn't send reply to plugin", underlyingError: error)
                        }
                    }

                case .testOperationRequest(let subset, let parameters):
                    self.invocationDelegate.pluginRequestedTestOperation(subset: .init(subset), parameters: .init(parameters)) {
                        do {
                            switch $0 {
                            case .success(let result):
                                responder(try HostToPluginMessage.testOperationResponse(result: .init(result)).toData())
                            case .failure(let error):
                                responder(try HostToPluginMessage.errorResponse(error: String(describing: error)).toData())
                            }
                        }
                        catch {
                            self.observabilityScope.emit(debug: "couldn't send reply to plugin", underlyingError: error)
                        }
                    }

                case .symbolGraphRequest(let targetName, let options):
                    // The plugin requested symbol graph information for a target. We ask the delegate and then send a response.
                    self.invocationDelegate.pluginRequestedSymbolGraph(forTarget: .init(targetName), options: .init(options)) {
                        do {
                            switch $0 {
                            case .success(let result):
                                responder(try HostToPluginMessage.symbolGraphResponse(result: .init(result)).toData())
                            case .failure(let error):
                                responder(try HostToPluginMessage.errorResponse(error: String(describing: error)).toData())
                            }
                        }
                        catch {
                            self.observabilityScope.emit(debug: "couldn't send reply to plugin", underlyingError: error)
                        }
                    }
                }
            }
        }
        let runnerDelegate = ScriptRunnerDelegate(invocationDelegate: delegate, observabilityScope: observabilityScope)

        // Call the plugin script runner to actually invoke the plugin.
        scriptRunner.runPluginScript(
            sourceFiles: sources.paths,
            pluginName: self.name,
            initialMessage: initialMessage,
            toolsVersion: self.apiVersion,
            workingDirectory: workingDirectory,
            writableDirectories: writableDirectories,
            readOnlyDirectories: readOnlyDirectories,
            allowNetworkConnections: allowNetworkConnections,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: callbackQueue,
            delegate: runnerDelegate) { result in
                dispatchPrecondition(condition: .onQueue(callbackQueue))
                completion(result.map { exitCode in
                    // Return a result based on the exit code or the `exitEarly` parameter. If the plugin
                    // exits with an error but hasn't already emitted an error, we do so for it.
                    let exitedCleanly = (exitCode == 0) && !runnerDelegate.exitEarly
                    if !exitedCleanly && !runnerDelegate.hasReportedError {
                        delegate.pluginEmittedDiagnostic(
                            .error("Plugin ended with exit code \(exitCode)")
                        )
                    }
                    return exitedCleanly
                })
        }
    }
}
