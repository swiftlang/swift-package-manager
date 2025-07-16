//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SwiftPMInternal) import Basics
import Foundation
import PackageGraph
import PackageLoading
import PackageModel
import TSCUtility

@_spi(SwiftPMInternal)
import SPMBuildCore

import func TSCBasic.topologicalSort
import var TSCBasic.stdoutStream

import enum SwiftBuild.ProjectModel

fileprivate func memoize<T>(to cache: inout T?, build: () async throws -> T) async rethrows -> T {
    if let value = cache {
        return value
    } else {
        let value = try await build()
        cache = value
        return value
    }
}

extension ModulesGraph {
    fileprivate static func computePluginGeneratedFiles(
        target: ResolvedModule,
        toolsVersion: ToolsVersion,
        additionalFileRules: [FileRuleDescription],
        buildParameters: BuildParameters,
        buildToolPluginInvocationResults: [PackagePIFBuilder.BuildToolPluginInvocationResult],
        prebuildCommandResults: [CommandPluginResult],
        observabilityScope: ObservabilityScope
    ) throws -> (pluginDerivedSources: Sources, pluginDerivedResources: [Resource]) {
        var pluginDerivedSources = Sources(paths: [], root: buildParameters.dataPath)

        // Add any derived files that were declared for any commands from plugin invocations.
        var pluginDerivedFiles = [AbsolutePath]()
        for command in buildToolPluginInvocationResults.reduce([], { $0 + $1.buildCommands }) {
            for absPath in command.outputPaths {
                pluginDerivedFiles.append(try AbsolutePath(validating: absPath))
            }
        }

        // Add any derived files that were discovered from output directories of prebuild commands.
        for result in prebuildCommandResults {
            for path in result.derivedFiles {
                pluginDerivedFiles.append(path)
            }
        }

        // Let `TargetSourcesBuilder` compute the treatment of plugin generated files.
        let (derivedSources, derivedResources) = TargetSourcesBuilder.computeContents(
            for: pluginDerivedFiles,
            toolsVersion: toolsVersion,
            additionalFileRules: additionalFileRules,
            defaultLocalization: target.defaultLocalization,
            targetName: target.name,
            targetPath: target.underlying.path,
            observabilityScope: observabilityScope
        )
        let pluginDerivedResources = derivedResources
        for absPath in derivedSources {
            let relPath = absPath.relative(to: pluginDerivedSources.root)
            pluginDerivedSources.relativePaths.append(relPath)
        }

        return (pluginDerivedSources, pluginDerivedResources)
    }
}

/// The parameters required by `PIFBuilder`.
struct PIFBuilderParameters {
    let triple: Basics.Triple

    /// Whether the toolchain supports `-package-name` option.
    let isPackageAccessModifierSupported: Bool

    /// Whether or not build for testability is enabled.
    let enableTestability: Bool

    /// Whether to create dylibs for dynamic library products.
    let shouldCreateDylibForDynamicProducts: Bool

    /// The path to the library directory of the active toolchain.
    let toolchainLibDir: AbsolutePath

    /// An array of paths to search for pkg-config `.pc` files.
    let pkgConfigDirectories: [AbsolutePath]

    /// The toolchain's SDK root path.
    let sdkRootPath: AbsolutePath?

    /// The Swift language versions supported by the SwiftBuild being used for the build.
    let supportedSwiftVersions: [SwiftLanguageVersion]

    /// The plugin script runner that will compile and run plugins.
    let pluginScriptRunner: PluginScriptRunner

    /// Disable the sandbox for the custom tasks
    let disableSandbox: Bool

    /// The working directory where the plugins should produce their results
    let pluginWorkingDirectory: AbsolutePath

    /// Additional rules for including a source or resource file in a target
    let additionalFileRules: [FileRuleDescription]
}

/// PIF object builder for a package graph.
public final class PIFBuilder {
    /// Name of the PIF target aggregating all targets (*excluding* tests).
    public static let allExcludingTestsTargetName = "AllExcludingTests"

    /// Name of the PIF target aggregating all targets (*including* tests).
    public static let allIncludingTestsTargetName = "AllIncludingTests"

    /// The package graph to build from.
    let graph: ModulesGraph

    /// The parameters used to configure the PIF.
    let parameters: PIFBuilderParameters

    /// The ObservabilityScope to emit diagnostics to.
    let observabilityScope: ObservabilityScope

    /// The file system to read from.
    let fileSystem: FileSystem

    /// Creates a `PIFBuilder` instance.
    /// - Parameters:
    ///   - graph: The package graph to build from.
    ///   - parameters: The parameters used to configure the PIF.
    ///   - fileSystem: The file system to read from.
    ///   - observabilityScope: The ObservabilityScope to emit diagnostics to.
    init(
        graph: ModulesGraph,
        parameters: PIFBuilderParameters,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
    ) {
        self.graph = graph
        self.parameters = parameters
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "PIF Builder")
    }

    /// Generates the PIF representation.
    /// - Parameters:
    ///   - prettyPrint: Whether to return a formatted JSON.
    ///   - preservePIFModelStructure: Whether to preserve model structure.
    /// - Returns: The package graph in the JSON PIF format.
    func generatePIF(
        prettyPrint: Bool = true,
        preservePIFModelStructure: Bool = false,
        printPIFManifestGraphviz: Bool = false,
        buildParameters: BuildParameters
    ) async throws -> String {
        let encoder = prettyPrint ? JSONEncoder.makeWithDefaults() : JSONEncoder()

        if !preservePIFModelStructure {
            encoder.userInfo[.encodeForSwiftBuild] = true
        }

        let topLevelObject = try await self.constructPIF(buildParameters: buildParameters)

        // Sign the PIF objects before encoding it for Swift Build.
        try PIF.sign(workspace: topLevelObject.workspace)

        let pifData = try encoder.encode(topLevelObject)
        let pifString = String(decoding: pifData, as: UTF8.self)

        if printPIFManifestGraphviz {
            // Print dot graph to stdout.
            writePIF(topLevelObject.workspace, toDOT: stdoutStream)
            stdoutStream.flush()

            // Abort the build process, ensuring we don't add
            // further noise to stdout (and break `dot` graph parsing).
            throw PIFGenerationError.printedPIFManifestGraphviz
        }

        return pifString
    }

    private var cachedPIF: PIF.TopLevelObject?

    /// Compute the available build tools, and their destination build path for host for each plugin.
    private func availableBuildPluginTools(
        graph: ModulesGraph,
        buildParameters: BuildParameters,
        pluginsPerModule: [ResolvedModule.ID: [ResolvedModule]],
        hostTriple: Basics.Triple
    ) async throws -> [ResolvedModule.ID: [String: PluginTool]] {
        var accessibleToolsPerPlugin: [ResolvedModule.ID: [String: PluginTool]] = [:]

        for (_, plugins) in pluginsPerModule {
            for plugin in plugins where accessibleToolsPerPlugin[plugin.id] == nil {
                // Determine the tools to which this plugin has access, and create a name-to-path mapping from tool
                // names to the corresponding paths. Built tools are assumed to be in the build tools directory.
                let accessibleTools = try await plugin.preparePluginTools(
                    fileSystem: fileSystem,
                    environment: buildParameters.buildEnvironment,
                    for: hostTriple
                ) { name, path in
                    return buildParameters.buildPath.appending(path)
                }

                accessibleToolsPerPlugin[plugin.id] = accessibleTools
            }
        }

        return accessibleToolsPerPlugin
    }

    /// Constructs a `PIF.TopLevelObject` representing the package graph.
    private func constructPIF(buildParameters: BuildParameters) async throws -> PIF.TopLevelObject {
        let pluginScriptRunner = self.parameters.pluginScriptRunner
        let outputDir = self.parameters.pluginWorkingDirectory.appending("outputs")

        let pluginsPerModule = graph.pluginsPerModule(
            satisfying: buildParameters.buildEnvironment // .buildEnvironment(for: .host)
        )

        let availablePluginTools = try await availableBuildPluginTools(
            graph: graph,
            buildParameters: buildParameters,
            pluginsPerModule: pluginsPerModule,
            hostTriple: try pluginScriptRunner.hostTriple
        )

        return try await memoize(to: &self.cachedPIF) {
            guard let rootPackage = self.graph.rootPackages.only else {
                if self.graph.rootPackages.isEmpty {
                    throw PIFGenerationError.rootPackageNotFound
                } else {
                    throw PIFGenerationError.multipleRootPackagesFound
                }
            }

            let sortedPackages = self.graph.packages
                .sorted { $0.manifest.displayName < $1.manifest.displayName } // TODO: use identity instead?
            
            var packagesAndProjects: [(ResolvedPackage, ProjectModel.Project)] = []
            
            for package in sortedPackages {
                var buildToolPluginResultsByTargetName: [String: [PackagePIFBuilder.BuildToolPluginInvocationResult]] = [:]

                for module in package.modules {
                    // Apply each build tool plugin used by the target in order,
                    // creating a list of results (one for each plugin usage).
                    var buildToolPluginResults: [PackagePIFBuilder.BuildToolPluginInvocationResult] = []

                    for plugin in module.pluginDependencies(satisfying: buildParameters.buildEnvironment) {
                        let pluginModule = plugin.underlying as! PluginModule

                        // Determine the tools to which this plugin has access, and create a name-to-path mapping from tool
                        // names to the corresponding paths. Built tools are assumed to be in the build tools directory.
                        guard let accessibleTools = availablePluginTools[plugin.id] else {
                            throw InternalError("No tools found for plugin \(plugin.name)")
                        }

                        // Assign a plugin working directory based on the package, target, and plugin.
                        let pluginOutputDir = outputDir.appending(
                            components: [
                                package.identity.description,
                                module.name,
                                buildParameters.destination == .host ? "tools" : "destination",
                                plugin.name,
                            ]
                        )

                        // Determine the set of directories under which plugins are allowed to write.
                        // We always include just the output directory, and for now there is no possibility
                        // of opting into others.
                        let writableDirectories = [outputDir]

                        // Determine a set of further directories under which plugins are never allowed
                        // to write, even if they are covered by other rules (such as being able to write
                        // to the temporary directory).
                        let readOnlyDirectories = [package.path]

                        // In tools version 6.0 and newer, we vend the list of files generated by previous plugins.
                        let pluginDerivedSources: Sources
                        let pluginDerivedResources: [Resource]
                        if package.manifest.toolsVersion >= .v6_0 {
                            // Set up dummy observability because we don't want to emit diagnostics for this before the actual
                            // build.
                            let observability = ObservabilitySystem { _, _ in }
                            // Compute the generated files based on all results we have computed so far.
                            (pluginDerivedSources, pluginDerivedResources) = try ModulesGraph.computePluginGeneratedFiles(
                                target: module,
                                toolsVersion: package.manifest.toolsVersion,
                                additionalFileRules: self.parameters.additionalFileRules,
                                buildParameters: buildParameters,
                                buildToolPluginInvocationResults: buildToolPluginResults,
                                prebuildCommandResults: [],
                                observabilityScope: observability.topScope
                            )
                        } else {
                            pluginDerivedSources = .init(paths: [], root: package.path)
                            pluginDerivedResources = []
                        }

                        let result = try await pluginModule.invoke(
                            module: plugin,
                            action: .createBuildToolCommands(
                                package: package,
                                target: module,
                                pluginGeneratedSources: pluginDerivedSources.paths,
                                pluginGeneratedResources: pluginDerivedResources.map(\.path)
                            ),
                            buildEnvironment: buildParameters.buildEnvironment,
                            scriptRunner: pluginScriptRunner,
                            workingDirectory: package.path,
                            outputDirectory: pluginOutputDir,
                            toolSearchDirectories: [buildParameters.toolchain.swiftCompilerPath.parentDirectory],
                            accessibleTools: accessibleTools,
                            writableDirectories: writableDirectories,
                            readOnlyDirectories: readOnlyDirectories,
                            allowNetworkConnections: [],
                            pkgConfigDirectories: self.parameters.pkgConfigDirectories,
                            sdkRootPath: buildParameters.toolchain.sdkRootPath,
                            fileSystem: fileSystem,
                            modulesGraph: self.graph,
                            observabilityScope: observabilityScope
                        )

                        let diagnosticsEmitter = observabilityScope.makeDiagnosticsEmitter {
                            var metadata = ObservabilityMetadata()
                            metadata.moduleName = module.name
                            metadata.pluginName = result.plugin.name
                            return metadata
                        }

                        for line in result.textOutput.split(whereSeparator: { $0.isNewline }) {
                            diagnosticsEmitter.emit(info: line)
                        }

                        for diag in result.diagnostics {
                            diagnosticsEmitter.emit(diag)
                        }

                        let result2 = PackagePIFBuilder.BuildToolPluginInvocationResult(
                            prebuildCommandOutputPaths: result.prebuildCommands.map( { $0.outputFilesDirectory } ),
                            buildCommands: result.buildCommands.map( { buildCommand in
                                var newEnv: Environment = buildCommand.configuration.environment

                                let runtimeLibPaths = buildParameters.toolchain.runtimeLibraryPaths

                                // Add paths to swift standard runtime libraries to the library path so that they can be found at runtime
                                for libPath in runtimeLibPaths {
                                    newEnv.appendPath(key: .libraryPath, value: libPath.pathString)
                                }

                                // Append the system path at the end so that necessary system tool paths can be found
                                if let pathValue = Environment.current[EnvironmentKey.path] {
                                    newEnv.appendPath(key: .path, value: pathValue)
                                }

                                let writableDirectories: [AbsolutePath] = [pluginOutputDir]

                                return PackagePIFBuilder.CustomBuildCommand(
                                    displayName: buildCommand.configuration.displayName,
                                    executable: buildCommand.configuration.executable.pathString,
                                    arguments: buildCommand.configuration.arguments,
                                    environment: .init(newEnv),
                                    workingDir: package.path,
                                    inputPaths: buildCommand.inputFiles,
                                    outputPaths: buildCommand.outputFiles.map(\.pathString),
                                    sandboxProfile:
                                        self.parameters.disableSandbox ?
                                            nil :
                                            .init(
                                                strictness: .writableTemporaryDirectory,
                                                writableDirectories: writableDirectories,
                                                readOnlyDirectories: buildCommand.inputFiles
                                            )
                                )
                            } )
                        )

                        // Add a BuildToolPluginInvocationResult to the mapping.
                        buildToolPluginResults.append(result2)
                        if var existingResults = buildToolPluginResultsByTargetName[module.name] {
                            existingResults.append(result2)
                        } else {
                            buildToolPluginResultsByTargetName[module.name] = [result2]
                        }
                    }
                }

                let packagePIFBuilderDelegate = PackagePIFBuilderDelegate(
                    package: package
                )
                let packagePIFBuilder = PackagePIFBuilder(
                    modulesGraph: self.graph,
                    resolvedPackage: package,
                    packageManifest: package.manifest,
                    delegate: packagePIFBuilderDelegate,
                    buildToolPluginResultsByTargetName: buildToolPluginResultsByTargetName,
                    createDylibForDynamicProducts: self.parameters.shouldCreateDylibForDynamicProducts,
                    packageDisplayVersion: package.manifest.displayName,
                    fileSystem: self.fileSystem,
                    observabilityScope: self.observabilityScope
                )
                
                try packagePIFBuilder.build()
                packagesAndProjects.append((package, packagePIFBuilder.pifProject))
            }
            
            var projects = packagesAndProjects.map(\.1)
            projects.append(
                try buildAggregateProject(
                    packagesAndProjects: packagesAndProjects,
                    observabilityScope: observabilityScope,
                    modulesGraph: graph,
                    buildParameters: buildParameters
                )
            )

            let workspace = PIF.Workspace(
                id: "Workspace:\(rootPackage.path.pathString)",
                name: rootPackage.manifest.displayName, // TODO: use identity instead?
                path: rootPackage.path,
                projects: projects
            )

            return PIF.TopLevelObject(workspace: workspace)
        }
    }

    // Convenience method for generating PIF.
    public static func generatePIF(
        buildParameters: BuildParameters,
        packageGraph: ModulesGraph,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        preservePIFModelStructure: Bool,
        pluginScriptRunner: PluginScriptRunner,
        disableSandbox: Bool,
        pluginWorkingDirectory: AbsolutePath,
        pkgConfigDirectories: [Basics.AbsolutePath],
        additionalFileRules: [FileRuleDescription]
    ) async throws -> String {
        let parameters = PIFBuilderParameters(
            buildParameters,
            supportedSwiftVersions: [],
            pluginScriptRunner: pluginScriptRunner,
            disableSandbox: disableSandbox,
            pluginWorkingDirectory: pluginWorkingDirectory,
            additionalFileRules: additionalFileRules,
        )
        let builder = Self(
            graph: packageGraph,
            parameters: parameters,
            fileSystem: fileSystem,
            observabilityScope: observabilityScope
        )
        return try await builder.generatePIF(preservePIFModelStructure: preservePIFModelStructure, buildParameters: buildParameters)
    }
}

fileprivate final class PackagePIFBuilderDelegate: PackagePIFBuilder.BuildDelegate {
    let package: ResolvedPackage
    
    init(package: ResolvedPackage) {
        self.package = package
    }
    
    var isRootPackage: Bool {
        self.package.manifest.packageKind.isRoot
    }
    
    var hostsOnlyPackages: Bool {
        false
    }
    
    var isUserManaged: Bool {
        true
    }
    
    var isBranchOrRevisionBased: Bool {
        false
    }
    
    func customProductType(forExecutable product: PackageModel.Product) -> ProjectModel.Target.ProductType? {
        nil
    }
    
    func deviceFamilyIDs() -> Set<Int> {
        []
    }
    
    func shouldPackagesBuildForARM64e(platform: PackageModel.Platform) -> Bool {
        false
    }

    var isPluginExecutionSandboxingDisabled: Bool {
        false
    }
    
    func configureProjectBuildSettings(_ buildSettings: inout ProjectModel.BuildSettings) {
        /* empty */
    }
    
    func configureSourceModuleBuildSettings(sourceModule: ResolvedModule, settings: inout ProjectModel.BuildSettings) {
        /* empty */
    }
    
    func customInstallPath(product: PackageModel.Product) -> String? {
        nil
    }
    
    func customExecutableName(product: PackageModel.Product) -> String? {
        nil
    }
    
    func customLibraryType(product: PackageModel.Product) -> PackageModel.ProductType.LibraryType? {
        nil
    }
    
    func customSDKOptions(forPlatform: PackageModel.Platform) -> [String] {
        []
    }
    
    func addCustomTargets(pifProject: inout SwiftBuild.ProjectModel.Project) throws -> [PackagePIFBuilder.ModuleOrProduct] {
        return []
    }
    
    func shouldSuppressProductDependency(product: PackageModel.Product, buildSettings: inout SwiftBuild.ProjectModel.BuildSettings) -> Bool {
        false
    }
    
    func shouldSetInstallPathForDynamicLib(productName: String) -> Bool {
        false
    }
    
    func configureLibraryProduct(
        product: PackageModel.Product,
        project: inout ProjectModel.Project,
        target: WritableKeyPath<ProjectModel.Project, ProjectModel.Target>,
        additionalFiles: WritableKeyPath<ProjectModel.Group, ProjectModel.Group>
    ) {
        /* empty */
    }
    
    func suggestAlignedPlatformVersionGiveniOSVersion(platform: PackageModel.Platform, iOSVersion: PackageModel.PlatformVersion) -> String? {
        nil
    }
    
    func validateMacroFingerprint(for macroModule: ResolvedModule) -> Bool {
        true
    }
}

fileprivate func buildAggregateProject(
    packagesAndProjects: [(package: ResolvedPackage, project: ProjectModel.Project)],
    observabilityScope: ObservabilityScope,
    modulesGraph: ModulesGraph,
    buildParameters: BuildParameters
) throws -> ProjectModel.Project {
    precondition(!packagesAndProjects.isEmpty)
    
    var aggregateProject = ProjectModel.Project(
        id: "AGGREGATE",
        path: packagesAndProjects[0].project.path,
        projectDir: packagesAndProjects[0].project.projectDir,
        name: "Aggregate",
        developmentRegion: "en"
    )
    observabilityScope.logPIF(.debug, "Created project '\(aggregateProject.id)' with name '\(aggregateProject.name)'")
    
    var settings = ProjectModel.BuildSettings()
    settings[.PRODUCT_NAME] = "$(TARGET_NAME)"
    settings[.SUPPORTED_PLATFORMS] = ["$(AVAILABLE_PLATFORMS)"]
    settings[.SDKROOT] = "auto"
    settings[.SDK_VARIANT] = "auto"
    settings[.SKIP_INSTALL] = "YES"
    
    aggregateProject.addBuildConfig { id in BuildConfig(id: id, name: "Debug", settings: settings) }
    aggregateProject.addBuildConfig { id in BuildConfig(id: id, name: "Release", settings: settings) }
    
    func addEmptyBuildConfig(
        to targetKeyPath: WritableKeyPath<ProjectModel.Project, ProjectModel.AggregateTarget>,
        name: String
    ) {
        let emptySettings = BuildSettings()
        aggregateProject[keyPath: targetKeyPath].common.addBuildConfig { id in
            BuildConfig(id: id, name: name, settings: emptySettings)
        }
    }
    
    let allIncludingTestsTargetKeyPath = try aggregateProject.addAggregateTarget { _ in
        ProjectModel.AggregateTarget(
            id: "ALL-INCLUDING-TESTS",
            name: PIFBuilder.allIncludingTestsTargetName
        )
    }
    addEmptyBuildConfig(to: allIncludingTestsTargetKeyPath, name: "Debug")
    addEmptyBuildConfig(to: allIncludingTestsTargetKeyPath, name: "Release")
    
    let allExcludingTestsTargetKeyPath = try aggregateProject.addAggregateTarget { _ in
        ProjectModel.AggregateTarget(
            id: "ALL-EXCLUDING-TESTS",
            name: PIFBuilder.allExcludingTestsTargetName
        )
    }
    addEmptyBuildConfig(to: allExcludingTestsTargetKeyPath, name: "Debug")
    addEmptyBuildConfig(to: allExcludingTestsTargetKeyPath, name: "Release")
    
    for (package, packageProject) in packagesAndProjects where package.manifest.packageKind.isRoot {
        for target in packageProject.targets {
            switch target {
            case .target(let target):
                guard !target.id.hasSuffix(.dynamic) else {
                    // Otherwise we hit a bunch of "Unknown multiple commands produce: ..." errors,
                    // as the build artifacts from "PACKAGE-TARGET:Foo"
                    // conflicts with those from "PACKAGE-TARGET:Foo-dynamic".
                    continue
                }

                if let resolvedModule = modulesGraph.module(for: target.name) {
                    guard modulesGraph.isInRootPackages(resolvedModule, satisfying: buildParameters.buildEnvironment) else {
                        // Disconnected target, possibly due to platform when condition that isn't satisfied
                        continue
                    }
                }

                aggregateProject[keyPath: allIncludingTestsTargetKeyPath].common.addDependency(
                    on: target.id,
                    platformFilters: [],
                    linkProduct: false
                )
                if ![.unitTest, .swiftpmTestRunner].contains(target.productType) {
                    aggregateProject[keyPath: allExcludingTestsTargetKeyPath].common.addDependency(
                        on: target.id,
                        platformFilters: [],
                        linkProduct: false
                    )
                }
            case .aggregate:
                break
            }
        }
    }
    
    do {
        let allIncludingTests = aggregateProject[keyPath: allIncludingTestsTargetKeyPath]
        let allExcludingTests = aggregateProject[keyPath: allExcludingTestsTargetKeyPath]
        
        observabilityScope.logPIF(
            .debug,
            indent: 1,
            "Created target '\(allIncludingTests.id)' with name '\(allIncludingTests.name)' " +
            "and \(allIncludingTests.common.dependencies.count) (unlinked) dependencies"
        )
        observabilityScope.logPIF(
            .debug,
            indent: 1,
            "Created target '\(allExcludingTests.id)' with name '\(allExcludingTests.name)' " +
            "and \(allExcludingTests.common.dependencies.count) (unlinked) dependencies"
        )
    }
    
    return aggregateProject
}

public enum PIFGenerationError: Error {
    case rootPackageNotFound, multipleRootPackagesFound
    
    case unsupportedSwiftLanguageVersions(
        targetName: String,
        versions: [SwiftLanguageVersion],
        supportedVersions: [SwiftLanguageVersion]
    )

    /// Early build termination when using `--print-pif-manifest-graph`.
    case printedPIFManifestGraphviz
}

extension PIFGenerationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .rootPackageNotFound:
            "No root package was found"

        case .multipleRootPackagesFound:
            "Multiple root packages were found, making the PIF generation (root packages) ordering sensitive"

        case .unsupportedSwiftLanguageVersions(
            targetName: let target,
            versions: let given,
            supportedVersions: let supported
        ):
            "None of the Swift language versions used in target '\(target)' settings are supported." +
            " (given: \(given), supported: \(supported))"

        case .printedPIFManifestGraphviz:
            "Printed PIF manifest as graphviz"
        }
    }
}

// MARK: - Helpers

extension PIFBuilderParameters {
    init(
        _ buildParameters: BuildParameters,
        supportedSwiftVersions: [SwiftLanguageVersion],
        pluginScriptRunner: PluginScriptRunner,
        disableSandbox: Bool,
        pluginWorkingDirectory: AbsolutePath,
        additionalFileRules: [FileRuleDescription]
    ) {
        self.init(
            triple: buildParameters.triple,
            isPackageAccessModifierSupported: buildParameters.driverParameters.isPackageAccessModifierSupported,
            enableTestability: buildParameters.enableTestability,
            shouldCreateDylibForDynamicProducts: buildParameters.shouldCreateDylibForDynamicProducts,
            toolchainLibDir: (try? buildParameters.toolchain.toolchainLibDir) ?? .root,
            pkgConfigDirectories: buildParameters.pkgConfigDirectories,
            sdkRootPath: buildParameters.toolchain.sdkRootPath,
            supportedSwiftVersions: supportedSwiftVersions,
            pluginScriptRunner: pluginScriptRunner,
            disableSandbox: disableSandbox,
            pluginWorkingDirectory: pluginWorkingDirectory,
            additionalFileRules: additionalFileRules,
        )
    }
}
