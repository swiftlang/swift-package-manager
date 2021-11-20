/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Foundation
import PackageModel
import PackageLoading
import PackageGraph
import TSCBasic
import TSCUtility

public typealias Diagnostic = Basics.Diagnostic

public enum PluginAction {
    case createBuildToolCommands(target: ResolvedTarget)
    case performCommand(targets: [ResolvedTarget], arguments: [String])
}

extension PluginTarget {
    /// Invokes the plugin by compiling its source code (if needed) and then running it as a subprocess. The specified
    /// plugin action determines which entry point is called in the subprocess, and the package and the tool mapping
    /// determine the context that is available to the plugin.
    ///
    /// The working directory should be a path in the file system into which the plugin is allowed to write information
    /// that persists between all invocations of a plugin for the same purpose. The exact meaning of "same" means here
    /// depends on the particular plugin; for a build tool plugin, it might be the combination of the plugin and target
    /// for which it is being invoked.
    ///
    /// Note that errors thrown by this function relate to problems actually invoking the plugin. Any diagnostics that
    /// are emitted by the plugin are contained in the returned result structure.
    ///
    /// - Parameters:
    ///   - action: The plugin action (i.e. entry point) to invoke, possibly containing parameters.
    ///   - package: The root of the package graph to pass down to the plugin.
    ///   - scriptRunner: Entity responsible for actually running the code of the plugin.
    ///   - outputDirectory: A directory under which the plugin can write anything it wants to.
    ///   - toolNamesToPaths: A mapping from name of tools available to the plugin to the corresponding absolute paths.
    ///   - fileSystem: The file system to which all of the paths refers.
    ///
    /// - Returns: A PluginInvocationResult that contains the results of invoking the plugin.
    public func invoke(
        action: PluginAction,
        package: ResolvedPackage,
        buildEnvironment: BuildEnvironment,
        scriptRunner: PluginScriptRunner,
        outputDirectory: AbsolutePath,
        toolNamesToPaths: [String: AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        completion: @escaping (Result<PluginInvocationResult, Error>) -> Void
    ) {
        // Create the plugin working directory if needed (but don't do anything with it if it already exists).
        do {
            try fileSystem.createDirectory(outputDirectory, recursive: true)
        }
        catch {
            return callbackQueue.async { completion(.failure(PluginEvaluationError.couldNotCreateOuputDirectory(path: outputDirectory, underlyingError: error))) }
        }

        // Create the input context to send to the plugin.
        var serializer = PluginScriptRunnerInputSerializer(buildEnvironment: buildEnvironment)
        let inputStruct: PluginScriptRunnerInput
        do {
            inputStruct = try serializer.makePluginScriptRunnerInput(
                rootPackage: package,
                pluginWorkDir: outputDirectory,
                builtProductsDir: outputDirectory,  // FIXME — what is this parameter needed for?
                toolNamesToPaths: toolNamesToPaths,
                pluginAction: action)
        }
        catch {
            return callbackQueue.async { completion(.failure(PluginEvaluationError.couldNotSerializePluginInput(underlyingError: error))) }
        }
        
        // Call the plugin script runner to actually invoke the plugin.
        var outputText = Data()
        scriptRunner.runPluginScript(
            sources: sources,
            input: inputStruct,
            toolsVersion: self.apiVersion,
            writableDirectories: [outputDirectory],
            fileSystem: fileSystem,
            observabilityScope: observabilityScope,
            callbackQueue: DispatchQueue(label: "plugin-invocation"),
            outputHandler: { data in
                outputText.append(contentsOf: data)
            },
            completion: { result in
                // Translate the PluginScriptRunnerOutput into a PluginInvocationResult.
                completion(result.tryMap { output in
                    // Generate emittable Diagnostics from the plugin output.
                    let diagnostics: [Diagnostic] = output.diagnostics.map { diag in
                        let metadata: ObservabilityMetadata? = diag.file.map {
                            var metadata = ObservabilityMetadata()
                            metadata.fileLocation = try? .init(.init(validating: $0), line: diag.line)
                            return metadata
                        }

                        switch diag.severity {
                        case .error:
                            return .error(diag.message, metadata: metadata)
                        case .warning:
                            return .warning(diag.message, metadata: metadata)
                        case .remark:
                            return .info(diag.message, metadata: metadata)
                        }
                    }

                    // FIXME: Validate the plugin output structure here, e.g. paths, etc.
                    
                    // Generate commands from the plugin output. This is where we translate from the transport JSON to our
                    // internal form. We deal with BuildCommands and PrebuildCommands separately.
                    // FIXME: This feels a bit too specific to have here.
                    // FIXME: Also there is too much repetition here, need to unify it.
                    let buildCommands = output.buildCommands.map { cmd in
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
                    let prebuildCommands = output.prebuildCommands.map { cmd in
                        PluginInvocationResult.PrebuildCommand(
                            configuration: .init(
                                displayName: cmd.displayName,
                                executable: cmd.executable,
                                arguments: cmd.arguments,
                                environment: cmd.environment,
                                workingDirectory: cmd.workingDirectory.map{ AbsolutePath($0) }),
                            outputFilesDirectory: AbsolutePath(cmd.outputFilesDirectory))
                    }

                    // Create and return an evaluation result for the invocation.
                    return PluginInvocationResult(
                        plugin: self,
                        diagnostics: diagnostics,
                        textOutput: String(decoding: outputText, as: UTF8.self),
                        buildCommands: buildCommands,
                        prebuildCommands: prebuildCommands)
                })
            })
    }
}

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
        buildEnvironment: BuildEnvironment,
        pluginScriptRunner: PluginScriptRunner,
        observabilityScope: ObservabilityScope,
        fileSystem: FileSystem
    ) throws -> [ResolvedTarget: [PluginInvocationResult]] {
        // TODO: Convert this to be asynchronous, taking a completion closure. This may require changes to the package
        // graph APIs to make them accessible concurrently.
        var pluginResultsByTarget: [ResolvedTarget: [PluginInvocationResult]] = [:]

        for target in self.reachableTargets.sorted(by: { $0.name < $1.name }) {
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
            guard let package = self.package(for: target) else {
                throw InternalError("could not determine package for target \(target)")
            }

            // Apply each plugin used by the target in order, creating a list of results (one for each plugin usage).
            var pluginResults: [PluginInvocationResult] = []
            for pluginTarget in pluginTargets {
                // Determine the tools to which this plugin has access, and create a name-to-path mapping from tool
                // names to the corresponding paths. Built tools are assumed to be in the build tools directory.
                let accessibleTools = pluginTarget.accessibleTools(for: pluginScriptRunner.hostTriple)
                let toolNamesToPaths = accessibleTools.reduce(into: [String: AbsolutePath](), { dict, tool in
                    switch tool {
                    case .builtTool(let name, let path):
                        dict[name] = builtToolsDir.appending(path)
                    case .vendedTool(let name, let path):
                        dict[name] = path
                    }
                })

                // Assign a plugin working directory based on the package, target, and plugin.
                let pluginOutputDir = outputDir.appending(components: package.identity.description, target.name, pluginTarget.name)

                // Invoke the plugin.
                let result = try tsc_await { pluginTarget.invoke(
                    action: .createBuildToolCommands(target: target),
                    package: package,
                    buildEnvironment: buildEnvironment,
                    scriptRunner: pluginScriptRunner,
                    outputDirectory: pluginOutputDir,
                    toolNamesToPaths: toolNamesToPaths,
                    fileSystem: fileSystem,
                    observabilityScope: observabilityScope,
                    callbackQueue: DispatchQueue(label: "plugin-invocation"),
                    completion: $0) }
                pluginResults.append(result)
            }

            // Associate the list of results with the target. The list will have one entry for each plugin used by the target.
            pluginResultsByTarget[target] = pluginResults
        }
        return pluginResultsByTarget
    }
}


/// A description of a tool to which a plugin has access.
public enum PluginAccessibleTool: Hashable {
    /// A tool that is built by an ExecutableTarget (the path is relative to the built-products directory).
    case builtTool(name: String, path: RelativePath)

    /// A tool that is vended by a BinaryTarget (the path is absolute and refers to an unpackaged binary target).
    case vendedTool(name: String, path: AbsolutePath)
}

public extension PluginTarget {

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
    case couldNotCreateOuputDirectory(path: AbsolutePath, underlyingError: Error)
    case couldNotSerializePluginInput(underlyingError: Error)
    case runningPluginFailed(underlyingError: Error)
    case decodingPluginOutputFailed(json: Data, underlyingError: Error)
}


/// Implements the mechanics of running a plugin script (implemented as a set of Swift source files) as a process.
public protocol PluginScriptRunner {

    /// Implements the mechanics of running a plugin script implemented as a set of Swift source files, for use
    /// by the package graph when it is evaluating package plugins.
    ///
    /// The `sources` refer to the Swift source files and are accessible in the provided `fileSystem`. The input is
    /// a PluginScriptRunnerInput structure, and the output will be a PluginScriptRunnerOutput structure.
    ///
    /// The text output callback handler will receive free-form output from the script as it's running. Structured
    /// diagnostics emitted by the plugin will be added to the observability scope.
    ///
    /// Every concrete implementation should cache any intermediates as necessary to avoid redundant work.
    func runPluginScript(
        sources: Sources,
        input: PluginScriptRunnerInput,
        toolsVersion: ToolsVersion,
        writableDirectories: [AbsolutePath],
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        callbackQueue: DispatchQueue,
        outputHandler: @escaping (Data) -> Void,
        completion: @escaping (Result<PluginScriptRunnerOutput, Error>) -> Void
    )

    /// Returns the Triple that represents the host for which plugin script tools should be built, or for which binary
    /// tools should be selected.
    var hostTriple: Triple { get }
}


/// Serializable context that's passed as input to an invocation of a plugin.
/// This is the transport data to a particular invocation of a plugin for a
/// particular purpose; everything we can communicate to the plugin is here.
///
/// It consists mainly of a flattened package graph, with each kind of entity
/// referenced by an array that is indexed by an ID (a small integer). This
/// structure is serialized from the package model (a directed acyclic graph).
/// All references in the flattened graph are ID numbers.
///
/// Other information includes a mapping from names of command line tools that
/// are available to the plugin to their corresponding paths, and a serialized
/// representation of the plugin action.
public struct PluginScriptRunnerInput: Codable {
    let paths: [Path]
    let targets: [Target]
    let products: [Product]
    let packages: [Package]
    let rootPackageId: Package.Id
    let pluginWorkDirId: Path.Id
    let builtProductsDirId: Path.Id
    let toolNamesToPathIds: [String: Path.Id]
    let pluginAction: PluginAction

    /// An action that SwiftPM can ask the plugin to take. This corresponds to
    /// the capabilities declared for the plugin.
    enum PluginAction: Codable {
        case createBuildToolCommands(targetId: Target.Id)
        case performCommand(targetIds: [Target.Id], arguments: [String])
    }

    /// A single absolute path in the wire structure, represented as a tuple
    /// consisting of the ID of the base path and subpath off of that path.
    /// This avoids repetition of path components in the wire representation.
    struct Path: Codable {
        typealias Id = Int
        let basePathId: Path.Id?
        let subpath: String
    }

    /// A package in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Package: Codable {
        typealias Id = Int
        let identity: String
        let displayName: String
        let directoryId: Path.Id
        let origin: Origin
        let toolsVersion: ToolsVersion
        let dependencies: [Dependency]
        let productIds: [Product.Id]
        let targetIds: [Target.Id]

        /// The origin of the package (root, local, repository, registry, etc).
        enum Origin: Codable {
            case root
            case local(
                path: Path.Id)
            case repository(
                url: String,
                displayVersion: String,
                scmRevision: String)
            case registry(
                identity: String,
                displayVersion: String)
        }

        /// Represents a version of SwiftPM on whose semantics a package relies.
        struct ToolsVersion: Codable {
            let major: Int
            let minor: Int
            let patch: Int
        }

        /// A dependency on a package in the wire structure. All references to
        /// other entities are ID numbers.
        struct Dependency: Codable {
            let packageId: Package.Id
        }
    }

    /// A product in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Product: Codable {
        typealias Id = Int
        let name: String
        let targetIds: [Target.Id]
        let info: ProductInfo

        /// Information for each type of product in the wire structure. All
        /// references to other entities are their ID numbers.
        enum ProductInfo: Codable {
            case executable(
                mainTargetId: Target.Id)
            case library(
                kind: LibraryKind)

            /// A type of library in the wire structure, as SwiftPM sees it.
            enum LibraryKind: Codable {
                case `static`
                case `dynamic`
                case automatic
            }
        }
    }

    /// A target in the wire structure. All references to other entities are
    /// their ID numbers.
    struct Target: Codable {
        typealias Id = Int
        let name: String
        let directoryId: Path.Id
        let dependencies: [Dependency]
        let info: TargetInfo

        /// A dependency on either a target or a product in the wire structure.
        /// All references to other entities are ID their numbers.
        enum Dependency: Codable {
            case target(
                targetId: Target.Id)
            case product(
                productId: Product.Id)
        }
        
        /// Type-specific information for a target in the wire structure. All
        /// references to other entities are their ID numbers.
        enum TargetInfo: Codable {
            /// Information about a Swift source module target.
            case swiftSourceModuleInfo(
                moduleName: String,
                sourceFiles: [File],
                compilationConditions: [String],
                linkedLibraries: [String],
                linkedFrameworks: [String])
            
            /// Information about a Clang source module target.
            case clangSourceModuleInfo(
                moduleName: String,
                sourceFiles: [File],
                preprocessorDefinitions: [String],
                headerSearchPaths: [String],
                publicHeadersDirId: Path.Id?,
                linkedLibraries: [String],
                linkedFrameworks: [String])
            
            /// Information about a binary artifact target.
            case binaryArtifactInfo(
                kind: BinaryArtifactKind,
                origin: BinaryArtifactOrigin,
                artifactId: Path.Id)
            
            /// Information about a system library target.
            case systemLibraryInfo(
                pkgConfig: String?,
                compilerFlags: [String],
                linkerFlags: [String])

            /// A file in the wire structure.
            struct File: Codable {
                let basePathId: Path.Id
                let name: String
                let type: FileType

                /// A type of file in the wire structure, as SwiftPM sees it.
                enum FileType: String, Codable {
                    case source
                    case header
                    case resource
                    case unknown
                }
            }
            
            /// A kind of binary artifact.
            enum BinaryArtifactKind: Codable {
                case xcframework
                case artifactsArchive
                case unknown
            }
            
            /// The origin of a binary artifact.
            enum BinaryArtifactOrigin: Codable {
                case local
                case remote(url: String)
            }
        }
    }
}

/// Creates the serialized input structure for the plugin script based on all
/// the input information to a plugin.
struct PluginScriptRunnerInputSerializer {
    let buildEnvironment: BuildEnvironment
    var paths: [PluginScriptRunnerInput.Path] = []
    var pathsToIds: [AbsolutePath: PluginScriptRunnerInput.Path.Id] = [:]
    var targets: [PluginScriptRunnerInput.Target] = []
    var targetsToIds: [ResolvedTarget: PluginScriptRunnerInput.Target.Id] = [:]
    var products: [PluginScriptRunnerInput.Product] = []
    var productsToIds: [ResolvedProduct: PluginScriptRunnerInput.Product.Id] = [:]
    var packages: [PluginScriptRunnerInput.Package] = []
    var packagesToIds: [ResolvedPackage: PluginScriptRunnerInput.Package.Id] = [:]
    
    mutating func makePluginScriptRunnerInput(
        rootPackage: ResolvedPackage,
        pluginWorkDir: AbsolutePath,
        builtProductsDir: AbsolutePath,
        toolNamesToPaths: [String: AbsolutePath],
        pluginAction: PluginAction
    ) throws -> PluginScriptRunnerInput {
        let rootPackageId = try serialize(package: rootPackage)
        let pluginWorkDirId = try serialize(path: pluginWorkDir)
        let builtProductsDirId = try serialize(path: builtProductsDir)
        let toolNamesToPathIds = try toolNamesToPaths.mapValues{ try serialize(path: $0) }
        let serializedPluginAction: PluginScriptRunnerInput.PluginAction
        switch pluginAction {
        case .createBuildToolCommands(let target):
            serializedPluginAction = .createBuildToolCommands(targetId: try serialize(target: target)!)
        case .performCommand(let targets, let arguments):
            serializedPluginAction = .performCommand(targetIds: try targets.compactMap { try serialize(target: $0) }, arguments: arguments)
        }
        return PluginScriptRunnerInput(
            paths: paths,
            targets: targets,
            products: products,
            packages: packages,
            rootPackageId: rootPackageId,
            pluginWorkDirId: pluginWorkDirId,
            builtProductsDirId: builtProductsDirId,
            toolNamesToPathIds: toolNamesToPathIds,
            pluginAction: serializedPluginAction)
    }
    
    /// Adds a path to the serialized structure, if it isn't already there.
    /// Either way, this function returns the path's wire ID.
    mutating func serialize(path: AbsolutePath) throws -> PluginScriptRunnerInput.Path.Id {
        // If we've already seen the path, just return the wire ID we already assigned to it.
        if let id = pathsToIds[path] { return id }
        
        // Split up the path into a base path and a subpath (currently always with the last path component as the
        // subpath, but this can be optimized where there are sequences of path components with a valence of one).
        let basePathId = (path.parentDirectory.isRoot ? nil : try serialize(path: path.parentDirectory))
        let subpathString = path.basename
        
        // Finally assign the next wire ID to the path and append a serialized Path record.
        let id = paths.count
        paths.append(.init(basePathId: basePathId, subpath: subpathString))
        pathsToIds[path] = id
        return id
    }

    // Adds a target to the serialized structure, if it isn't already there and
    // if it is of a kind that should be passed to the plugin. If so, this func-
    // tion returns the target's wire ID. If not, it returns nil.
    mutating func serialize(target: ResolvedTarget) throws -> PluginScriptRunnerInput.Target.Id? {
        // If we've already seen the target, just return the wire ID we already assigned to it.
        if let id = targetsToIds[target] { return id }
        
        // Construct the FileList
        var targetFiles: [PluginScriptRunnerInput.Target.TargetInfo.File] = []
        targetFiles.append(contentsOf: try target.underlyingTarget.sources.paths.map {
            .init(basePathId: try serialize(path: $0.parentDirectory), name: $0.basename, type: .source)
        })
        targetFiles.append(contentsOf: try target.underlyingTarget.resources.map {
            .init(basePathId: try serialize(path: $0.path.parentDirectory), name: $0.path.basename, type: .resource)
        })
        targetFiles.append(contentsOf: try target.underlyingTarget.others.map {
            .init(basePathId: try serialize(path: $0.parentDirectory), name: $0.basename, type: .unknown)
        })
        
        // Create a scope for evaluating build settings.
        let scope = BuildSettings.Scope(target.underlyingTarget.buildSettings, environment: buildEnvironment)
        
        // Look at the target and decide what to serialize. At this point we may decide to not serialize it at all.
        let targetInfo: PluginScriptRunnerInput.Target.TargetInfo
        switch target.underlyingTarget {
            
        case let target as SwiftTarget:
            targetInfo = .swiftSourceModuleInfo(
                moduleName: target.c99name,
                sourceFiles: targetFiles,
                compilationConditions: scope.evaluate(.SWIFT_ACTIVE_COMPILATION_CONDITIONS),
                linkedLibraries: scope.evaluate(.LINK_LIBRARIES),
                linkedFrameworks: scope.evaluate(.LINK_FRAMEWORKS))

        case let target as ClangTarget:
            targetInfo = .clangSourceModuleInfo(
                moduleName: target.c99name,
                sourceFiles: targetFiles,
                preprocessorDefinitions: scope.evaluate(.GCC_PREPROCESSOR_DEFINITIONS),
                headerSearchPaths: scope.evaluate(.HEADER_SEARCH_PATHS),
                publicHeadersDirId: try serialize(path: target.includeDir),
                linkedLibraries: scope.evaluate(.LINK_LIBRARIES),
                linkedFrameworks: scope.evaluate(.LINK_FRAMEWORKS))

        case let target as SystemLibraryTarget:
            var cFlags: [String] = []
            var ldFlags: [String] = []
            // FIXME: What do we do with any diagnostics here?
            let observabilityScope = ObservabilitySystem({ _, _ in }).topScope
            for result in pkgConfigArgs(for: target, fileSystem: localFileSystem, observabilityScope: observabilityScope) {
                if let error = result.error {
                    observabilityScope.emit(
                        warning: "\(error)",
                        metadata: .pkgConfig(pcFile: result.pkgConfigName, targetName: target.name)
                    )
                }
                else {
                    cFlags += result.cFlags
                    ldFlags += result.libs
                }
            }

            targetInfo = .systemLibraryInfo(
                pkgConfig: target.pkgConfig,
                compilerFlags: cFlags,
                linkerFlags: ldFlags)
            
        case let target as BinaryTarget:
            let artifactKind: PluginScriptRunnerInput.Target.TargetInfo.BinaryArtifactKind
            switch target.kind {
            case .artifactsArchive:
                artifactKind = .artifactsArchive
            case .xcframework:
                artifactKind = .xcframework
            case .unknown:
                artifactKind = .unknown
            }
            let artifactOrigin: PluginScriptRunnerInput.Target.TargetInfo.BinaryArtifactOrigin
            switch target.origin {
            case .local:
                artifactOrigin = .local
            case .remote(let url):
                artifactOrigin = .remote(url: url)
            }
            targetInfo = .binaryArtifactInfo(
                kind: artifactKind,
                origin: artifactOrigin,
                artifactId: try serialize(path: target.artifactPath))
            
        default:
            // It's not a type of target that we pass through to the plugin.
            return nil
        }
        
        // We only get this far if we are serializing the target. If so we also serialize its dependencies.
        let dependencies: [PluginScriptRunnerInput.Target.Dependency] = try target.dependencies(satisfying: buildEnvironment).compactMap {
            switch $0 {
            case .target(let target, _):
                return try serialize(target: target).map { .target(targetId: $0) }
            case .product(let product, _):
                return try serialize(product: product).map { .product(productId: $0) }
            }
        }

        // Finally assign the next wire ID to the target and append a serialized Target record.
        let id = targets.count
        targets.append(.init(
            name: target.name,
            directoryId: try serialize(path: target.sources.root),
            dependencies: dependencies,
            info: targetInfo))
        targetsToIds[target] = id
        return id
    }

    // Adds a product to the serialized structure, if it isn't already there and
    // if it is of a kind that should be passed to the plugin. If so, this func-
    // tion returns the product's wire ID. If not, it returns nil.
    mutating func serialize(product: ResolvedProduct) throws -> PluginScriptRunnerInput.Product.Id? {
        // If we've already seen the product, just return the wire ID we already assigned to it.
        if let id = productsToIds[product] { return id }
        
        // Look at the product and decide what to serialize. At this point we may decide to not serialize it at all.
        let productInfo: PluginScriptRunnerInput.Product.ProductInfo
        switch product.type {
            
        case .executable:
            guard let mainExecTarget = product.targets.first(where: { $0.type == .executable }) else {
                throw InternalError("could not determine main executable target for product \(product)")
            }
            guard let mainExecTargetId = try serialize(target: mainExecTarget) else {
                throw InternalError("unable to serialize main executable target \(mainExecTarget) for product \(product)")
            }
            productInfo = .executable(mainTargetId: mainExecTargetId)

        case .library(let kind):
            switch kind {
            case .static:
                productInfo = .library(kind: .static)
            case .dynamic:
                productInfo = .library(kind: .dynamic)
            case .automatic:
                productInfo = .library(kind: .automatic)
            }

        default:
            // It's not a type of product that we pass through to the plugin.
            return nil
        }
        
        // Finally assign the next wire ID to the product and append a serialized Product record.
        let id = products.count
        products.append(.init(
            name: product.name,
            targetIds: try product.targets.compactMap{ try serialize(target: $0) },
            info: productInfo))
        productsToIds[product] = id
        return id
    }

    // Adds a package to the serialized structure, if it isn't already there.
    // Either way, this function returns the target's wire ID.
    mutating func serialize(package: ResolvedPackage) throws -> PluginScriptRunnerInput.Package.Id {
        // If we've already seen the package, just return the wire ID we already assigned to it.
        if let id = packagesToIds[package] { return id }
        
        // Determine how we should represent the origin of the package to the plugin.
        func origin(for package: ResolvedPackage) throws -> PluginScriptRunnerInput.Package.Origin {
            switch package.manifest.packageKind {
            case .root(_):
                return .root
            case .fileSystem(let path):
                return .local(path: try serialize(path: path))
            case .localSourceControl(let path):
                return .repository(url: path.asURL.absoluteString, displayVersion: String(describing: package.manifest.version), scmRevision: String(describing: package.manifest.revision))
            case .remoteSourceControl(let url):
                return .repository(url: url.absoluteString, displayVersion: String(describing: package.manifest.version), scmRevision: String(describing: package.manifest.revision))
            case .registry(let identity):
                return .registry(identity: identity.description, displayVersion: String(describing: package.manifest.version))
            }
        }

        // Assign the next wire ID to the package and append a serialized Package record.
        let id = packages.count
        packages.append(.init(
            identity: package.identity.description,
            displayName: package.manifest.displayName,
            directoryId: try serialize(path: package.path),
            origin: try origin(for: package),
            toolsVersion: .init(
                major: package.manifest.toolsVersion.major,
                minor: package.manifest.toolsVersion.minor,
                patch: package.manifest.toolsVersion.patch),
            dependencies: try package.dependencies.map{ .init(packageId: try serialize(package: $0)) },
            productIds: try package.products.compactMap{ try serialize(product: $0) },
            targetIds: try package.targets.compactMap{ try serialize(target: $0) }))
        packagesToIds[package] = id
        return id
    }
}


/// Deserializable result that's received as output from the invocation of the plugin. This is the transport data from
/// the invocation of the plugin for a particular target; everything the plugin can commuicate to us is here.
public struct PluginScriptRunnerOutput: Codable {
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

extension ObservabilityMetadata {
    public var fileLocation: FileLocation? {
        get {
            self[FileLocationKey.self]
        }
        set {
            self[FileLocationKey.self] = newValue
        }
    }

    private enum FileLocationKey: Key {
        typealias Value = FileLocation
    }
}

public struct FileLocation: Equatable, CustomStringConvertible {
    public let file: AbsolutePath
    public let line: Int?

    public init(_ file: AbsolutePath, line: Int?) {
        self.file = file
        self.line = line
    }

    public var description: String {
        "\(self.file)\(self.line?.description.appending(" ") ?? "")"
    }
}
