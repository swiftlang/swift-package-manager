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
import TSCUtility


extension PackageGraph {

    /// Traverses the graph of reachable targets in a package graph, and applies plugins to targets as needed. Each
    /// plugin is passed an input context that provides information about the target to which it is being applied
    /// (along with some information about that target's dependency closure). The plugin is expected to generate an
    /// output in the form of commands that will later be run before or during the build, and can also emit debug
    /// output and diagnostics.
    ///
    /// This function returns a dictionary mapping the resolved targets that specify at least one plugin to the
    /// results of invoking those plugins in order. Each result includes an ordered list of commands to run before
    /// the build of the target, and another of the commands to incorporate into the build graph so they run during
    /// the build.
    ///
    /// This function may cache anything it wants to under the `cacheDir` directory. The `builtToolsDir` directory
    /// is where executables for any dependencies of targets will be made available. Any warnings and errors related
    /// to running the plugin will be emitted to `diagnostics`, and this function will throw an error if evaluation
    /// of any plugin fails.
    ///
    /// Note that warnings emitted by the the plugin itself will be returned in the PluginEvaluationResult structures
    /// for later showing to the user, and not added directly to the diagnostics engine.
    public func invokePlugins(
        outputDir: AbsolutePath,
        builtToolsDir: AbsolutePath,
        pluginScriptRunner: PluginScriptRunner,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> [ResolvedTarget: [PluginInvocationResult]] {
        // TODO: Convert this to be asynchronous, taking a completion closure. This may require changes to the package
        // graph APIs to make them accessible concurrently.
        var pluginResultsByTarget: [ResolvedTarget: [PluginInvocationResult]] = [:]
        
        for target in self.reachableTargets.sorted(by: { $0.name < $1.name }) {
            // Infer plugins from the declared dependencies, and collect them as well as any regular dependnencies.  Although plugin usage is declared separately from dependencies in the manifest, in the internal model we currently consider both to be dependencies.
            var pluginTargets: [PluginTarget] = []
            var dependencyTargets: [Target] = []
            for dependency in target.dependencies {
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
            guard let package = self.package(for: target) else {
                throw InternalError("could not determine package for target \(target)")
            }
            
            // Apply each plugin used by the target in order, creating a list of results (one for each plugin usage).
            var pluginResults: [PluginInvocationResult] = []
            for pluginTarget in pluginTargets {
                // Determine the tools to which this plugin has access, and create a name-to-path mapping from tool
                // names to the corresponding paths. Built tools are assumed to be in the build tools directory.
                let accessibleTools = pluginTarget.accessibleTools(for: pluginScriptRunner.hostTriple)
                let tools = accessibleTools.reduce(into: [String: PluginScriptRunnerInput.Tool](), { partial, tool in
                    switch tool {
                    case .builtTool(let name, let path):
                        partial[name] = .init(name: name, path: builtToolsDir.appending(path).pathString)
                    case .vendedTool(let name, let path):
                        partial[name] = .init(name: name, path: path.pathString)
                    }
                })
                
                // Give each invocation of a plugin a separate output directory.
                let pluginOutputDir = outputDir.appending(components: package.identity.description, target.name, pluginTarget.name)
                do {
                    try fileSystem.createDirectory(pluginOutputDir, recursive: true)
                }
                catch {
                    throw PluginEvaluationError.outputDirectoryCouldNotBeCreated(path: pluginOutputDir, underlyingError: error)
                }
                
                // Create the input context to pass when applying the plugin to the target.
                var inputFiles: [PluginScriptRunnerInput.FileInfo] = []
                inputFiles += target.underlyingTarget.sources.paths.map{ .init(path: $0.pathString, type: .source) }
                inputFiles += target.underlyingTarget.resources.map{ .init(path: $0.path.pathString, type: .resource) }
                inputFiles += target.underlyingTarget.others.map{ .init(path: $0.pathString, type: .unknown) }
                
                let pluginInput = PluginScriptRunnerInput(
                    targetName: target.name,
                    moduleName: target.c99name,
                    targetDirectory: target.sources.root.pathString,
                    packageDirectory: package.path.pathString,
                    inputFiles: .init(files: inputFiles),
                    dependencies: dependencyTargets.map {
                        .init(targetName: $0.name, moduleName: $0.c99name, targetDirectory: $0.sources.root.pathString)
                    },
                    pluginWorkDirectory: pluginOutputDir.pathString,
                    builtProductsDirectory: builtToolsDir.pathString,
                    tools: tools
                )
                
                // Run the plugin in the context of the target. The details of this are left to the plugin runner.
                // TODO: This should be asynchronous.
                let (pluginOutput, emittedText) = try runPluginScript(
                    sources: pluginTarget.sources,
                    input: pluginInput,
                    toolsVersion: package.manifest.toolsVersion,
                    writableDirectories: [pluginOutputDir],
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
                
                // Extract any emitted text output (received from the stdout/stderr of the plugin invocation).
                let textOutput = String(decoding: emittedText, as: UTF8.self)

                // FIXME: Validate the plugin output structure here, e.g. paths, etc.
                
                // Generate commands from the plugin output. This is where we translate from the transport JSON to our
                // internal form. We deal with BuildCommands and PrebuildCommands separately.
                let buildCommands = pluginOutput.buildCommands.map { cmd in
                    PluginInvocationResult.BuildCommand(
                        configuration: .init(
                            displayName: cmd.displayName,
                            executable: cmd.executable,
                            arguments: cmd.arguments,
                            environment: cmd.environment,
                            workingDirectory: cmd.workingDirectory.map{ AbsolutePath($0) }),
                        inputFiles: cmd.inputFiles.map{ AbsolutePath($0) },
                        outputFiles: cmd.outputFiles.map{ AbsolutePath($0) })
                }
                let prebuildCommands = pluginOutput.prebuildCommands.map { cmd in
                    PluginInvocationResult.PrebuildCommand(
                        configuration: .init(
                            displayName: cmd.displayName,
                            executable: cmd.executable,
                            arguments: cmd.arguments,
                            environment: cmd.environment,
                            workingDirectory: cmd.workingDirectory.map{ AbsolutePath($0) }),
                        outputFilesDirectory: AbsolutePath(cmd.outputFilesDirectory))
                }
                
                // Create an evaluation result from the usage of the plugin by the target.
                pluginResults.append(PluginInvocationResult(plugin: pluginTarget, diagnostics: diagnostics, textOutput: textOutput, buildCommands: buildCommands, prebuildCommands: prebuildCommands))
            }
            
            // Associate the list of results with the target. The list will have one entry for each plugin used by the target.
            pluginResultsByTarget[target] = pluginResults
        }
        return pluginResultsByTarget
    }
    
    
    /// Private helper function that serializes a PluginEvaluationInput as input JSON, calls the plugin runner to invoke the plugin, and finally deserializes the output JSON it emits to a PluginEvaluationOutput.  Adds any errors or warnings to `diagnostics`, and throws an error if there was a failure.
    /// FIXME: This should be asynchronous, taking a queue and a completion closure.
    fileprivate func runPluginScript(
        sources: Sources,
        input: PluginScriptRunnerInput,
        toolsVersion: ToolsVersion,
        writableDirectories: [AbsolutePath],
        pluginScriptRunner: PluginScriptRunner,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (output: PluginScriptRunnerOutput, stdoutText: Data) {
        // Serialize the PluginEvaluationInput to JSON.
        let encoder = JSONEncoder()
        let inputJSON = try encoder.encode(input)
        
        // Call the plugin runner.
        let (outputJSON, stdoutText) = try pluginScriptRunner.runPluginScript(
            sources: sources,
            inputJSON: inputJSON,
            toolsVersion: toolsVersion,
            writableDirectories: writableDirectories,
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


/// A description of a tool to which a plugin has access.
enum PluginAccessibleTool: Hashable {
    /// A tool that is built by an ExecutableTarget (the path is relative to the built-products directory).
    case builtTool(name: String, path: RelativePath)
    
    /// A tool that is vended by a BinaryTarget (the path is absolute and refers to an unpackaged binary target).
    case vendedTool(name: String, path: AbsolutePath)
}

extension PluginTarget {
    
    /// The set of tools that are accessible to this plugin.
    func accessibleTools(for hostTriple: Triple) -> Set<PluginAccessibleTool> {
        return Set(self.dependencies.flatMap { dependency -> [PluginAccessibleTool] in
            if case .target(let target, _) = dependency {
                // For a binary target we create a `vendedTool`.
                if let target = target as? BinaryTarget {
                    // TODO: Memoize this result for the host triple
                    guard let execInfos = try? target.parseArtifactArchives(for: hostTriple, fileSystem: localFileSystem) else {
                        // TODO: Deal better with errors in parsing the artifacts
                        return []
                    }
                    return execInfos.map{ .vendedTool(name: $0.name, path: $0.executablePath) }
                }
                // For an executable target we create a `builtTool`.
                else if target.type == .executable {
                    // TODO: How do we determine what the executable name will be for the host platform?
                    return [.builtTool(name: target.name, path: RelativePath(target.name))]
                }
            }
            return []
        })
    }
}


/// Represents the result of invoking a plugin for a particular target.  The result includes generated build
/// commands as well as any diagnostics and stdout/stderr output emitted by the plugin.
public struct PluginInvocationResult {
    /// The plugin that produced the results.
    public var plugin: PluginTarget
    
    /// Any diagnostics emitted by the plugin.
    public var diagnostics: [Diagnostic]
    
    /// Any textual output emitted by the plugin.
    public var textOutput: String

    /// The build commands generated by the plugin (in the order in which they should run).
    public var buildCommands: [BuildCommand]

    /// The prebuild commands generated by the plugin (in the order in which they should run).
    public var prebuildCommands: [PrebuildCommand]
    
    /// A command to incorporate into the build graph so that it runs during the build whenever it needs to. In
    /// particular it will run whenever any of the specified output files are missing or when the input files have
    /// changed from the last time when it ran.
    ///
    /// This is the preferred kind of command to generate when the input and output paths are known before the
    /// command is run (i.e. when the outputs depend only on the names of the inputs, not on their contents).
    /// The specified output files are processed in the same way as the target's source files.
    public struct BuildCommand {
        public var configuration: CommandConfiguration
        public var inputFiles: [AbsolutePath]
        public var outputFiles: [AbsolutePath]
    }

    /// A command to run before the start of every build. The command is expected to populate the output directory
    /// with any files that should be processed in the same way as the target's source files.
    public struct PrebuildCommand {
        // TODO: In the future these should be folded into regular build commands when the build system can handle not
        // knowing the names of all the outputs before the command runs.
        public var configuration: CommandConfiguration
        public var outputFilesDirectory: AbsolutePath
    }

    /// Launch configuration of a command that can be run (including a display name to show in logs etc).
    public struct CommandConfiguration {
        public var displayName: String
        public var executable: String
        public var arguments: [String]
        public var environment: [String: String]
        public var workingDirectory: AbsolutePath?
    }
    
    /// A location representing a file name or path and an optional line number.
    // FIXME: This should be part of the Diagnostics APIs.
    struct FileLineLocation: DiagnosticLocation {
        var file: String
        var line: Int?
        var description: String {
            "\(file)\(line.map{":\($0)"} ?? "")"
        }
    }
}


/// An error in plugin evaluation.
public enum PluginEvaluationError: Swift.Error {
    case outputDirectoryCouldNotBeCreated(path: AbsolutePath, underlyingError: Error)
    case runningPluginFailed(underlyingError: Error)
    case decodingPluginOutputFailed(json: Data, underlyingError: Error)
}


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
        writableDirectories: [AbsolutePath],
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data)
    
    /// Returns the Triple that represents the host for which plugin script tools should be built, or for which binary
    /// tools should be selected.
    var hostTriple: Triple { get }
}


/// Serializable context that's passed as input to the invocation of the plugin. This is the transport data to the in-
/// vocation of the plugin for a particular target; everything we can communicate to the plugin is here.
struct PluginScriptRunnerInput: Codable {
    var targetName: String
    var moduleName: String
    var targetDirectory: String
    var packageDirectory: String
    var inputFiles: FileList
    struct FileList: Codable {
        var files: [FileInfo]
    }
    struct FileInfo: Codable {
        var path: String
        var type: FileType
    }
    enum FileType: String, Codable {
        case source
        case resource
        case unknown
    }
    var dependencies: [DependencyTargetInfo]
    struct DependencyTargetInfo: Codable {
        var targetName: String
        var moduleName: String
        var targetDirectory: String
        var publicHeadersDirectory: String?
    }
    var pluginWorkDirectory: String
    var builtProductsDirectory: String
    var tools: [String: Tool]
    struct Tool: Codable {
        var name: String
        var path: String
    }
}


/// Deserializable result that's received as output from the invocation of the plugin. This is the transport data from
/// the invocation of the plugin for a particular target; everything the plugin can commuicate to us is here.
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
    let buildCommands: [BuildCommand]
    struct BuildCommand: Codable {
        let displayName: String
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String?
        let inputFiles: [String]
        let outputFiles: [String]
    }
    let prebuildCommands: [PrebuildCommand]
    struct PrebuildCommand: Codable {
        let displayName: String
        let executable: String
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: String?
        let outputFilesDirectory: String
    }
}
