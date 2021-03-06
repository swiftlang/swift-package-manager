/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Basics
import PackageModel
import PackageGraph
import TSCBasic


extension PackageGraph {

    /// Traverses the graph of reachable targets in a package graph and evaluates plugins as needed.  Each plugin is passed an input context that provides information about the target to which it is being applied (and some information from its dependency closure), and can generate an output in the form of commands that will later be run during the build.  This function returns a mapping of resolved targets to the results of running each of the plugins against the target in turn.  This include an ordered list of generated commands to run for each plugin capability.  This function may cache anything it wants to under the `cacheDir` directory.  The `execsDir` directory is where executables for any dependencies of targets will be made available.  Any warnings and errors related to running the plugin will be emitted to `diagnostics`, and this function will throw an error if evaluation of any plugin fails.  Note that warnings emitted by the the plugin itself will be returned in the PluginEvaluationResult structures and not added directly to the diagnostics engine.
    public func invokePlugins(
        buildEnvironment: BuildEnvironment,
        execsDir: AbsolutePath,
        outputDir: AbsolutePath,
        pluginScriptRunner: PluginScriptRunner,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> [ResolvedTarget: [PluginInvocationResult]] {
        // TODO: Convert this to be asynchronous, taking a completion closure.  This may require changes to package graph APIs.
        var evalResultsByTarget: [ResolvedTarget: [PluginInvocationResult]] = [:]
        
        for target in self.reachableTargets {
            // Infer plugins from the declared dependencies, and collect them as well as any regular dependnencies.  Although plugin usage is declared separately from dependencies in the manifest, in the internal model we currently consider both to be dependencies.
            var pluginTargets: [PluginTarget] = []
            var dependencyTargets: [Target] = []
            for dependency in target.dependencies(satisfying: buildEnvironment) {
                switch dependency {
                case .target(let target, _):
                    if let pluginTarget = target.underlyingTarget as? PluginTarget {
                        pluginTargets.append(pluginTarget)
                    }
                    else {
                        dependencyTargets.append(target.underlyingTarget)
                    }
                case .product(let product, _):
                    pluginTargets.append(contentsOf: product.targets.compactMap{ $0.underlyingTarget as? PluginTarget })
                }
            }
            
            // Leave quickly in the common case of not using any plugins.
            if pluginTargets.isEmpty {
                continue
            }
            
            /// Determine the package that contains the target.
            guard let package = self.packages.first(where: { $0.targets.contains(target) }) else {
                throw InternalError("could not find package for target \(target)")
            }
            
            // Evaluate each plugin in turn, creating a list of results (one for each plugin used by the target).
            var evalResults: [PluginInvocationResult] = []
            for pluginTarget in pluginTargets {
                // Give each invocation of an extension a separate output directory.
                let extOutputDir = outputDir.appending(components: package.name, target.name, pluginTarget.name)
                do {
                    try fileSystem.createDirectory(extOutputDir, recursive: true)
                }
                catch {
                    throw PluginEvaluationError.outputDirectoryCouldNotBeCreated(path: extOutputDir, underlyingError: error)
                }
                
                // Create the input context to pass to the plugin.
                let pluginInput = PluginScriptRunnerInput(
                    targetName: target.name,
                    moduleName: target.c99name,
                    targetDir: target.sources.root.pathString,
                    packageDir: package.path.pathString,
                    sourceFiles: target.sources.paths.map{ $0.pathString },
                    resourceFiles: target.underlyingTarget.resources.map{ $0.path.pathString },
                    otherFiles: target.underlyingTarget.others.map { $0.pathString },
                    dependencies: dependencyTargets.map {
                        .init(targetName: $0.name, moduleName: $0.c99name, targetDir: $0.sources.root.pathString)
                    },
                    outputDir: extOutputDir.pathString,
                    toolsDir: execsDir.pathString
                )
                
                // Run the plugin in the context of the target, and generate commands from the output.
                // TODO: This should be asynchronous.
                let (pluginOutput, emittedText) = try runPluginScript(
                    sources: pluginTarget.sources,
                    input: pluginInput,
                    toolsVersion: package.manifest.toolsVersion,
                    pluginScriptRunner: pluginScriptRunner,
                    diagnostics: diagnostics,
                    fileSystem: fileSystem
                )
                
                // Generate emittable Diagnostics from the plugin output.
                let diagnostics: [Diagnostic] = pluginOutput.diagnostics.map { diag in
                    // FIXME: The implementation here is unfortunate; better Diagnostic APIs would make it cleaner.
                    let location = diag.file.map {
                        PluginInvocationResult.FileLineLocation(file: $0, line: diag.line)
                    }
                    let message: Diagnostic.Message
                    switch diag.severity {
                    case .error: message = .error(diag.message)
                    case .warning: message = .warning(diag.message)
                    case .remark: message = .remark(diag.message)
                    }
                    if let location = location {
                        return Diagnostic(message: message, location: location)
                    }
                    else {
                        return Diagnostic(message: message)
                    }
                }
                
                // Generate commands from the plugin output.  This is where we translate from the transport JSON to our internal form.
                let commands: [PluginInvocationResult.Command] = pluginOutput.commands.map { cmd in
                    let displayName = cmd.displayName
                    let executable = cmd.executable
                    let arguments = cmd.arguments
                    let environment = cmd.environment
                    let workingDir = cmd.workingDirectory.map{ AbsolutePath($0) }
                    switch pluginTarget.capability {
                    case .prebuild:
                        return .prebuildCommand(
                            displayName: displayName,
                            executable: executable,
                            arguments: arguments,
                            environment: environment ?? [:],
                            workingDir: workingDir)
                    case .buildTool:
                        return .buildToolCommand(
                            displayName: displayName,
                            executable: executable,
                            arguments: arguments,
                            environment: environment ?? [:],
                            workingDir: workingDir,
                            inputPaths: cmd.inputPaths.map{ AbsolutePath($0) },
                            outputPaths: cmd.outputPaths.map{ AbsolutePath($0) })
                    case .postbuild:
                        return .postbuildCommand(
                            displayName: displayName,
                            executable: executable,
                            arguments: arguments,
                            environment: environment ?? [:],
                            workingDir: workingDir)
                    }
                }
                
                // Extract any emitted text output, the paths of any derived source files, and the paths of any output directories that should affect the validity of the build plan.
                let textOutput = String(decoding: emittedText, as: UTF8.self)
                let generatedOutputFiles = pluginOutput.generatedOutputFiles.map{ AbsolutePath($0) }
                let prebuildOutputDirectories = pluginOutput.prebuildOutputDirectories.map{ AbsolutePath($0) }

                // Create an evaluation result from the usage of the plugin by the target.
                evalResults.append(PluginInvocationResult(plugin: pluginTarget, commands: commands, diagnostics: diagnostics, derivedSourceFiles: generatedOutputFiles, prebuildOutputDirectories: prebuildOutputDirectories, textOutput: textOutput))
            }
            
            // Associate the list of results with the target.  The list will have one entry for each plugin used by the target.
            evalResultsByTarget[target] = evalResults
        }
        return evalResultsByTarget
    }
    
    @available(*, deprecated, message: "used evaluationPlugins() instead")
    public func evaluateExtensions(
        buildEnvironment: BuildEnvironment,
        execsDir: AbsolutePath,
        outputDir: AbsolutePath,
        extensionRunner: PluginScriptRunner,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> [ResolvedTarget: [PluginInvocationResult]] {
        return try self.invokePlugins(
            buildEnvironment: buildEnvironment,
            execsDir: execsDir,
            outputDir: outputDir,
            pluginScriptRunner: extensionRunner,
            diagnostics: diagnostics,
            fileSystem: fileSystem)
    }
    
    
    /// Private helper function that serializes a PluginEvaluationInput as input JSON, calls the plugin runner to invoke the plugin, and finally deserializes the output JSON it emits to a PluginEvaluationOutput.  Adds any errors or warnings to `diagnostics`, and throws an error if there was a failure.
    /// FIXME: This should be asynchronous, taking a queue and a completion closure.
    fileprivate func runPluginScript(sources: Sources, input: PluginScriptRunnerInput, toolsVersion: ToolsVersion, pluginScriptRunner: PluginScriptRunner, diagnostics: DiagnosticsEngine, fileSystem: FileSystem) throws -> (output: PluginScriptRunnerOutput, stdoutText: Data) {
        // Serialize the PluginEvaluationInput to JSON.
        let encoder = JSONEncoder()
        let inputJSON = try encoder.encode(input)
        
        // Call the plugin runner.
        let (outputJSON, stdoutText) = try pluginScriptRunner.runPluginScript(
            sources: sources,
            inputJSON: inputJSON,
            toolsVersion: toolsVersion,
            diagnostics: diagnostics,
            fileSystem: fileSystem)

        // Deserialize the JSON to an PluginScriptRunnerOutput.
        let output: PluginScriptRunnerOutput
        do {
            let decoder = JSONDecoder()
            output = try decoder.decode(PluginScriptRunnerOutput.self, from: outputJSON)
        }
        catch {
            throw PluginEvaluationError.decodingPluginOutputFailed(json: outputJSON, underlyingError: error)
        }
        return (output: output, stdoutText: stdoutText)
    }
}


/// Represents the result of invoking a plugin for a particular target.  The result includes generated build
/// commands as well as any diagnostics or output emitted by the plugin.
public struct PluginInvocationResult {
    /// The plugin that produced the results.
    public var plugin: PluginTarget
    
    /// The commands generated by the plugin (in order).
    public var commands: [Command]

    /// A command provided by a plugin. Plugins are evaluated after package graph resolution (and subsequently,
    /// if conditions change). Each plugin specifies capabilities the capability it provides, which determines what
    /// kinds of commands it generates (when they run during the build, and the specific semantics surrounding them).
    public enum Command {
        
        /// A command to run before the start of every build.
        case prebuildCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                environment: [String: String],
                workingDir: AbsolutePath?
             )
        
        /// A command to be incorporated into the build graph, so that it runs when any of the outputs are missing or
        /// the inputs have changed from the last time when it ran. This is the preferred kind of command to generate
        /// when the input and output paths are known.  The input and output dependencies determine when the command
        /// should be run during the build.
        case buildToolCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                environment: [String: String],
                workingDir: AbsolutePath?,
                inputPaths: [AbsolutePath],
                outputPaths: [AbsolutePath]
             )
        
        /// A command to run after the end of every build.
        case postbuildCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                environment: [String: String],
                workingDir: AbsolutePath?
             )
    }
    
    /// Any diagnostics emitted by the plugin.
    public var diagnostics: [Diagnostic]
    
    /// A location representing a file name or path and an optional line number.
    // FIXME: This should be part of the Diagnostics APIs.
    struct FileLineLocation: DiagnosticLocation {
        var file: String
        var line: Int?
        var description: String {
            "\(file)\(line.map{":\($0)"} ?? "")"
        }
    }
    
    /// Any generated output files that should be have build rules applied to them.
    public var derivedSourceFiles: [AbsolutePath]
    
    /// Any directories whose contents should affect the validity of the build plan.
    public var prebuildOutputDirectories: [AbsolutePath]

    /// Any textual output emitted by the plugin.
    public var textOutput: String
}
public typealias ExtensionEvaluationResult = PluginInvocationResult


/// An error in plugin evaluation.
public enum PluginEvaluationError: Swift.Error {
    case outputDirectoryCouldNotBeCreated(path: AbsolutePath, underlyingError: Error)
    case runningPluginFailed(underlyingError: Error)
    case decodingPluginOutputFailed(json: Data, underlyingError: Error)
}
public typealias ExtensionEvaluationError = PluginEvaluationError


/// Implements the mechanics of running a plugin script (implemented as a set of Swift source files) as a process.
public protocol PluginScriptRunner {
    
    /// Implements the mechanics of running a plugin script implemented as a set of Swift source files, for use
    /// by the package graph when it is evaluating package plugins.
    ///
    /// The `sources` refer to the Swift source files and are accessible in the provided `fileSystem`. The input is
    /// a serialized PluginEvaluationContext, and the output should be a serialized PluginEvaluationOutput as
    /// well as any free-form output produced by the script (for debugging purposes).
    ///
    /// Any errors or warnings related to the running of the plugin will be added to `diagnostics`.  Any errors
    /// or warnings emitted by the plugin itself will be part of the returned output.
    ///
    /// Every concrete implementation should cache any intermediates as necessary for fast evaluation.
    func runPluginScript(
        sources: Sources,
        inputJSON: Data,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data)

    @available(*, deprecated, message: "use runPluginScript() instead")
    func runExtension(
        sources: Sources,
        inputJSON: Data,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data)
}
extension PluginScriptRunner {
    public func runPluginScript(
        sources: Sources,
        inputJSON: Data,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data) {
        return try self.runExtension(
            sources: sources,
            inputJSON: inputJSON,
            toolsVersion: toolsVersion,
            diagnostics: diagnostics,
            fileSystem: fileSystem)
    }
    public func runExtension(
        sources: Sources,
        inputJSON: Data,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data) {
        return try self.runPluginScript(
            sources: sources,
            inputJSON: inputJSON,
            toolsVersion: toolsVersion,
            diagnostics: diagnostics,
            fileSystem: fileSystem)
    }
}
public typealias ExtensionRunner = PluginScriptRunner


/// Serializable context that's passed as input to the evaluation of the extension.
struct PluginScriptRunnerInput: Codable {
    var targetName: String
    var moduleName: String
    var targetDir: String
    var packageDir: String
    var sourceFiles: [String]
    var resourceFiles: [String]
    var otherFiles: [String]
    var dependencies: [DependencyTarget]
    public struct DependencyTarget: Codable {
        var targetName: String
        var moduleName: String
        var targetDir: String
    }
    var outputDir: String
    var toolsDir: String
}


/// Deserializable result that's received as output from the evaluation of the extension.
struct PluginScriptRunnerOutput: Codable {
    var version: Int
    var diagnostics: [Diagnostic]
    struct Diagnostic: Codable {
        enum Severity: String, Codable {
            case error, warning, remark
        }
        let severity: Severity
        let message: String
        let file: String?
        let line: Int?
    }

    let commands: [GeneratedCommand]
    struct GeneratedCommand: Codable {
        let displayName: String
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
        let environment: [String: String]?
        let inputPaths: [String]
        let outputPaths: [String]
    }

    var generatedOutputFiles: [String] = []
    var prebuildOutputDirectories: [String] = []
}
