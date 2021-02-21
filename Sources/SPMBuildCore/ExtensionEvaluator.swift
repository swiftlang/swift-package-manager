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

    /// Traverses the graph of reachable targets in a package graph and evaluates extensions as needed.  Each extension is passed an input context that provides information about the target to which it is being applied (and some information from its dependency closure), and can generate an output in the form of commands that will later be run during the build.  This function returns a mapping of resolved targets to the results of running each of the extensions against the target in turn.  This include an ordered list of generated commands to run for each extension capability.  This function may cache anything it wants to under the `cacheDir` directory.  The `execsDir` directory is where executables for any dependencies of targets will be made available.  Any warnings and errors related to running the extension will be emitted to `diagnostics`, and this function will throw an error if evaluation of any extension fails.  Note that warnings emitted by the the extension itself will be returned in the ExtensionEvaluationResult structures and not added directly to the diagnostics engine.
    public func evaluateExtensions(
        buildEnvironment: BuildEnvironment,
        execsDir: AbsolutePath,
        outputDir: AbsolutePath,
        extensionRunner: ExtensionRunner,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> [ResolvedTarget: [ExtensionEvaluationResult]] {
        // TODO: Convert this to be asynchronous, taking a completion closure.  This may require changes to package graph APIs.
        var evalResultsByTarget: [ResolvedTarget: [ExtensionEvaluationResult]] = [:]
        
        for target in self.reachableTargets {
            // Infer extensions from the declared dependencies, and collect them as well as any regular dependnencies.
            // TODO: We'll want to separate out extension usages from dependencies, but for now we get them from dependencies.
            var extensionTargets: [ExtensionTarget] = []
            var dependencyTargets: [Target] = []
            for dependency in target.dependencies(satisfying: buildEnvironment) {
                switch dependency {
                case .target(let target, _):
                    if let extensionTarget = target.underlyingTarget as? ExtensionTarget {
                        extensionTargets.append(extensionTarget)
                    }
                    else {
                        dependencyTargets.append(target.underlyingTarget)
                    }
                case .product(let product, _):
                    extensionTargets.append(contentsOf: product.targets.compactMap{ $0.underlyingTarget as? ExtensionTarget })
                }
            }
            
            // Leave quickly in the common case of not using any extensions.
            if extensionTargets.isEmpty {
                continue
            }
            
            // If this target does use any extensions, create the input context to pass to them.
            // FIXME: We'll want to decide on what directories to provide to the extenion
            guard let package = self.packages.first(where: { $0.targets.contains(target) }) else {
                throw InternalError("could not find package for target \(target)")
            }
            let extOutputsDir = outputDir.appending(components: "extensions", package.name, target.c99name, "outputs")
            let extCachesDir = outputDir.appending(components: "extensions", package.name, target.c99name, "caches")
            let extensionInput = ExtensionEvaluationInput(
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
                // FIXME: We'll want to adjust these output locations
                outputDir: extOutputsDir.pathString,
                cacheDir: extCachesDir.pathString,
                execsDir: execsDir.pathString,
                options: [:]
            )
            
            // Evaluate each extension in turn, creating a list of results (one for each extension used by the target).
            var evalResults: [ExtensionEvaluationResult] = []
            for extTarget in extensionTargets {
                // Create the output and cache directories, if needed.
                do {
                    try fileSystem.createDirectory(extOutputsDir, recursive: true)
                }
                catch {
                    throw ExtensionEvaluationError.outputDirectoryCouldNotBeCreated(path: extOutputsDir, underlyingError: error)
                }
                do {
                    try fileSystem.createDirectory(extCachesDir, recursive: true)
                }
                catch {
                    throw ExtensionEvaluationError.outputDirectoryCouldNotBeCreated(path: extCachesDir, underlyingError: error)
                }
                
                // Run the extension in the context of the target, and generate commands from the output.
                // TODO: This should be asynchronous.
                let (extensionOutput, emittedText) = try runExtension(
                    sources: extTarget.sources,
                    input: extensionInput,
                    toolsVersion: package.manifest.toolsVersion,
                    extensionRunner: extensionRunner,
                    diagnostics: diagnostics,
                    fileSystem: fileSystem
                )
                
                // Generate emittable Diagnostics from the extension output.
                let diagnostics: [Diagnostic] = extensionOutput.diagnostics.map { diag in
                    // FIXME: The implementation here is unfortunate; better Diagnostic APIs would make it cleaner.
                    let location = diag.file.map {
                        ExtensionEvaluationResult.FileLineLocation(file: $0, line: diag.line)
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
                
                // Generate commands from the extension output.
                let commands: [ExtensionEvaluationResult.Command] = extensionOutput.commands.map { cmd in
                    let displayName = cmd.displayName
                    let executable = cmd.executable
                    let arguments = cmd.arguments
                    let workingDir = cmd.workingDirectory.map{ AbsolutePath($0) }
                    let environment = cmd.environment
                    switch extTarget.capability {
                    case .prebuild:
                        let derivedSourceDirPaths = cmd.derivedSourcePaths.map{ AbsolutePath($0) }
                        return .prebuildCommand(displayName: displayName, executable: executable, arguments: arguments, workingDir: workingDir, environment: environment, derivedSourceDirPaths: derivedSourceDirPaths)
                    case .buildTool:
                        let inputPaths = cmd.inputPaths.map{ AbsolutePath($0) }
                        let outputPaths = cmd.outputPaths.map{ AbsolutePath($0) }
                        let derivedSourcePaths = cmd.derivedSourcePaths.map{ AbsolutePath($0) }
                        return .buildToolCommand(displayName: displayName, executable: executable, arguments: arguments, workingDir: workingDir, environment: environment, inputPaths: inputPaths, outputPaths: outputPaths, derivedSourcePaths: derivedSourcePaths)
                    case .postbuild:
                        return .postbuildCommand(displayName: displayName, executable: executable, arguments: arguments, workingDir: workingDir, environment: environment)
                    }
                }
                
                // Create an evaluation result from the usage of the extension by the target.
                let textOutput = String(decoding: emittedText, as: UTF8.self)
                evalResults.append(ExtensionEvaluationResult(extension: extTarget, commands: commands, diagnostics: diagnostics, textOutput: textOutput))
            }
            
            // Associate the list of results with the target.  The list will have one entry for each extension used by the target.
            evalResultsByTarget[target] = evalResults
        }
        return evalResultsByTarget
    }
    
    
    /// Private helper function that serializes an ExtensionEvaluationInput as input JSON, calls the extension runner to invoke the extension, and finally deserializes the output JSON it emits to a ExtensionEvaluationOutput.  Adds any errors or warnings to `diagnostics`, and throws an error if there was a failure.
    /// FIXME: This should be asynchronous, taking a queue and a completion closure.
    fileprivate func runExtension(sources: Sources, input: ExtensionEvaluationInput, toolsVersion: ToolsVersion, extensionRunner: ExtensionRunner, diagnostics: DiagnosticsEngine, fileSystem: FileSystem) throws -> (output: ExtensionEvaluationOutput, stdoutText: Data) {
        // Serialize the ExtensionEvaluationInput to JSON.
        let encoder = JSONEncoder()
        let inputJSON = try encoder.encode(input)
        
        // Call the extension runner.
        let (outputJSON, stdoutText) = try extensionRunner.runExtension(sources: sources, inputJSON: inputJSON, toolsVersion: toolsVersion, diagnostics: diagnostics, fileSystem: fileSystem)

        // Deserialize the JSON to an ExtensionEvaluationOutput.
        let output: ExtensionEvaluationOutput
        do {
            let decoder = JSONDecoder()
            output = try decoder.decode(ExtensionEvaluationOutput.self, from: outputJSON)
        }
        catch {
            throw ExtensionEvaluationError.decodingExtensionOutputFailed(json: outputJSON, underlyingError: error)
        }
        return (output: output, stdoutText: stdoutText)
    }
}


/// Represents the result of evaluating an extension against a particular resolved-target.  This includes generated
/// commands as well as any diagnostics or output emitted by the extension.
public struct ExtensionEvaluationResult {
    /// The extension that produced the results.
    public let `extension`: ExtensionTarget
    
    /// The commands generated by the extension (in order).
    public let commands: [Command]

    /// A command provided by an extension. Extensions are evaluated after package graph resolution (and subsequently,
    /// if conditions change). Each extension specifies capabilities the capability it provides, which determines what
    /// kinds of commands it generates (when they run during the build, and the specific semantics surrounding them).
    public enum Command {
        
        /// A command to run before the start of every build. Besides the obvious parameters, it can provide a list of
        /// directories whose contents should be considered as inputs to the set of source files to which build rules
        /// should be applied.
        case prebuildCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                workingDir: AbsolutePath?,
                environment: [String: String]?,
                derivedSourceDirPaths: [AbsolutePath]
             )
        
        /// A command to be incorporated into the build graph, so that it runs when any of the outputs are missing or
        /// the inputs have changed from the last time when it ran. This is the preferred kind of command to generate
        /// when the input and output paths are known. In addition to inputs and outputs, the command can specify one
        /// or more files that should be considered as inputs to the set of source files to which build rules should
        /// be applied.
        case buildToolCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                workingDir: AbsolutePath?,
                environment: [String: String]?,
                inputPaths: [AbsolutePath],
                outputPaths: [AbsolutePath],
                derivedSourcePaths: [AbsolutePath]
             )
        
        /// A command to run after the end of every build.
        case postbuildCommand(
                displayName: String,
                executable: String,
                arguments: [String],
                workingDir: AbsolutePath?,
                environment: [String: String]?
             )
    }
    
    // Any diagnostics emitted by the extension.
    public let diagnostics: [Diagnostic]
    
    // A location representing a file name or path and an optional line number.
    // FIXME: This should be part of the Diagnostics APIs.
    struct FileLineLocation: DiagnosticLocation {
        let file: String
        let line: Int?
        var description: String {
            "\(file)\(line.map{":\($0)"} ?? "")"
        }
    }
    
    // Any textual output emitted by the extension.
    public let textOutput: String
}


/// An error in extension evaluation.
public enum ExtensionEvaluationError: Swift.Error {
    case outputDirectoryCouldNotBeCreated(path: AbsolutePath, underlyingError: Error)
    case runningExtensionFailed(underlyingError: Error)
    case decodingExtensionOutputFailed(json: Data, underlyingError: Error)
}


/// Implements the mechanics of running an extension script (implemented as a set of Swift source files) as a process.
public protocol ExtensionRunner {
    
    /// Implements the mechanics of running an extension script implemented as a set of Swift source files, for use
    /// by the package graph when it is evaluating package extensions.
    ///
    /// The `sources` refer to the Swift source files and are accessible in the provided `fileSystem`. The input is
    /// a serialized ExtensionEvaluationContext, and the output should be a serialized ExtensionEvaluationOutput as
    /// well as any free-form output produced by the script (for debugging purposes).
    ///
    /// Any errors or warnings related to the running of the extension will be added to `diagnostics`.  Any errors
    /// or warnings emitted by the extension itself will be part of the returned output.
    ///
    /// Every concrete implementation should cache any intermediates as necessary for fast evaluation.
    func runExtension(
        sources: Sources,
        inputJSON: Data,
        toolsVersion: ToolsVersion,
        diagnostics: DiagnosticsEngine,
        fileSystem: FileSystem
    ) throws -> (outputJSON: Data, stdoutText: Data)
}


/// Serializable context that's passed as input to the evaluation of the extension.
struct ExtensionEvaluationInput: Codable {
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
    var cacheDir: String
    var execsDir: String
    var options: [String: String]
}


/// Deserializable result that's received as output from the evaluation of the extension.
struct ExtensionEvaluationOutput: Codable {
    let version: Int
    let diagnostics: [Diagnostic]
    struct Diagnostic: Codable {
        enum Severity: String, Codable {
            case error, warning, remark
        }
        let severity: Severity
        let message: String
        let file: String?
        let line: Int?
    }

    var commands: [GeneratedCommand]
    struct GeneratedCommand: Codable {
        let displayName: String
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
        let environment: [String: String]?
        let inputPaths: [String]
        let outputPaths: [String]
        let derivedSourcePaths: [String]
    }
}
