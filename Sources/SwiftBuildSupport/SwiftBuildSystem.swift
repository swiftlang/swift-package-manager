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

@_spi(SwiftPMInternal)
import Basics
import Dispatch
import class Foundation.FileManager
import class Foundation.JSONEncoder
import class Foundation.NSArray
import class Foundation.NSDictionary
import PackageGraph
import PackageModel
import PackageLoading

@_spi(SwiftPMInternal)
import SPMBuildCore

import class Basics.AsyncProcess
import func TSCBasic.memoize
import protocol TSCBasic.OutputByteStream
import func TSCBasic.withTemporaryFile

import enum TSCUtility.Diagnostics
import class TSCUtility.JSONMessageStreamingParser
import protocol TSCUtility.JSONMessageStreamingParserDelegate
import struct TSCBasic.RegEx

import var TSCBasic.stdoutStream

import class Build.SwiftCompilerOutputParser
import protocol Build.SwiftCompilerOutputParserDelegate
import struct Build.SwiftCompilerMessage

// TODO bp
import class SWBCore.SwiftCommandOutputParser

import Foundation
import SWBBuildService
import SwiftBuild


struct SessionFailedError: Error {
    var error: Error
    var diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
}

func withService<T>(
    connectionMode: SWBBuildServiceConnectionMode = .default,
    variant: SWBBuildServiceVariant = .default,
    serviceBundleURL: URL? = nil,
    body: @escaping (_ service: SWBBuildService) async throws -> T
) async throws -> T {
    let service = try await SWBBuildService(connectionMode: connectionMode, variant: variant, serviceBundleURL: serviceBundleURL)
    let result: T
    do {
        result = try await body(service)
    } catch {
        await service.close()
        throw error
    }
    await service.close()
    return result
}

public func createSession(
    service: SWBBuildService,
    name: String,
    toolchainPath: Basics.AbsolutePath,
    packageManagerResourcesDirectory: Basics.AbsolutePath?
) async throws-> (SWBBuildServiceSession, [SwiftBuildMessage.DiagnosticInfo]) {
    // SWIFT_EXEC and SWIFT_EXEC_MANIFEST may need to be overridden in debug scenarios in order to pick up Open Source toolchains
    let sessionResult = if toolchainPath.components.contains(where: { $0.hasSuffix(".app") }) {
        await service.createSession(name: name, developerPath: nil, resourceSearchPaths: packageManagerResourcesDirectory.map { [$0.pathString] } ?? [], cachePath: nil, inferiorProductsPath: nil, environment: nil)
    } else {
        await service.createSession(name: name, swiftToolchainPath: toolchainPath.pathString, resourceSearchPaths: packageManagerResourcesDirectory.map { [$0.pathString] } ?? [], cachePath: nil, inferiorProductsPath: nil, environment: nil)
    }
    switch sessionResult {
    case (.success(let session), let diagnostics):
        return (session, diagnostics)
    case (.failure(let error), let diagnostics):
        throw SessionFailedError(error: error, diagnostics: diagnostics)
    }
}

func withSession(
    service: SWBBuildService,
    name: String,
    toolchainPath: Basics.AbsolutePath,
    packageManagerResourcesDirectory: Basics.AbsolutePath?,
    body: @escaping (
        _ session: SWBBuildServiceSession,
        _ diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
    ) async throws -> Void
) async throws {
    let (session, diagnostics) = try await createSession(service: service, name: name, toolchainPath: toolchainPath, packageManagerResourcesDirectory: packageManagerResourcesDirectory)
    do {
        try await body(session, diagnostics)
    } catch let bodyError {
        do {
            try await session.close()
        } catch _ {
            // Assumption is that the first error is the most important one
            throw bodyError
        }

        throw bodyError
    }
    do {
        try await session.close()
    } catch {
        throw SessionFailedError(error: error, diagnostics: diagnostics)
    }
}

private final class PlanningOperationDelegate: SWBPlanningOperationDelegate, Sendable {
    public func provisioningTaskInputs(
        targetGUID: String,
        provisioningSourceData: SWBProvisioningTaskInputsSourceData
    ) async -> SWBProvisioningTaskInputs {
        let identity = provisioningSourceData.signingCertificateIdentifier
        if identity == "-" {
            let signedEntitlements = provisioningSourceData.entitlementsDestination == "Signature"
                ? provisioningSourceData.productTypeEntitlements.merging(
                    ["application-identifier": .plString(provisioningSourceData.bundleIdentifier)],
                    uniquingKeysWith: { _, new in new }
                ).merging(provisioningSourceData.projectEntitlements ?? [:], uniquingKeysWith: { _, new in new })
                : [:]

            let simulatedEntitlements = provisioningSourceData.entitlementsDestination == "__entitlements"
                ? provisioningSourceData.productTypeEntitlements.merging(
                    ["application-identifier": .plString(provisioningSourceData.bundleIdentifier)],
                    uniquingKeysWith: { _, new in new }
                ).merging(provisioningSourceData.projectEntitlements ?? [:], uniquingKeysWith: { _, new in new })
                : [:]

            return SWBProvisioningTaskInputs(
                identityHash: "-",
                identityName: "-",
                profileName: nil,
                profileUUID: nil,
                profilePath: nil,
                designatedRequirements: nil,
                signedEntitlements: signedEntitlements.merging(
                    provisioningSourceData.sdkRoot.contains("simulator") ? ["get-task-allow": .plBool(true)] : [:],
                    uniquingKeysWith: { _, new in new }
                ),
                simulatedEntitlements: simulatedEntitlements,
                appIdentifierPrefix: nil,
                teamIdentifierPrefix: nil,
                isEnterpriseTeam: nil,
                keychainPath: nil,
                errors: [],
                warnings: []
            )
        } else if identity.isEmpty {
            return SWBProvisioningTaskInputs()
        } else {
            return SWBProvisioningTaskInputs(
                identityHash: "-",
                errors: [
                    [
                        "description": "unable to supply accurate provisioning inputs for CODE_SIGN_IDENTITY=\(identity)\"",
                    ],
                ]
            )
        }
    }

    public func executeExternalTool(
        commandLine: [String],
        workingDirectory: String?,
        environment: [String: String]
    ) async throws -> SWBExternalToolResult {
        .deferred
    }
}

private final class SWBOutputDelegate: SPMBuildCore.BuildSystemDelegate {
    func buildSystem(_ buildSystem: BuildSystem, willStartCommand command: BuildSystemCommand) {
        print("SWBDELEGATE will start command")
    }
    func buildSystem(_ buildSystem: BuildSystem, didStartCommand command: BuildSystemCommand) {
        print("SWBDELEGATE did start command")

    }
    func buildSystem(_ buildSystem: BuildSystem, didUpdateTaskProgress text: String) {
        print("SWBDELEGATE did Update Task Progress")

    }
    func buildSystem(_ buildSystem: BuildSystem, didFinishCommand command: BuildSystemCommand) {
        print("SWBDELEGATE did finish command")

    }
    func buildSystemDidDetectCycleInRules(_ buildSystem: BuildSystem) {
        print("SWBDELEGATE detect cycle")

    }
    func buildSystem(_ buildSystem: BuildSystem, didFinishWithResult success: Bool) {
        print("SWBDELEGATE did finish with result: \(success)")
    }
    func buildSystemDidCancel(_ buildSystem: BuildSystem) {
        print("SWBDELEGATE did cancel")
    }

}

extension SwiftCompilerMessage {
    fileprivate var verboseProgressText: String? {
        switch kind {
        case .began(let info):
            ([info.commandExecutable] + info.commandArguments).joined(separator: " ")
        case .skipped, .finished, .abnormal, .signalled, .unparsableOutput:
            nil
        }
    }

    fileprivate var standardOutput: String? {
        switch kind {
        case .finished(let info),
             .abnormal(let info),
             .signalled(let info):
            info.output
        case .unparsableOutput(let output):
            output
        case .skipped, .began:
            nil
        }
    }
}


extension SwiftBuildSystemOutputParser: SwiftCompilerOutputParserDelegate {
    func swiftCompilerOutputParser(_ parser: Build.SwiftCompilerOutputParser, didParse message: Build.SwiftCompilerMessage) {
        // TODO bp
        if self.logLevel.isVerbose {
            if let text = message.verboseProgressText {
                self.outputStream.send("\(text)\n")
                self.outputStream.flush()
            }
        } else if !self.logLevel.isQuiet {
//            self.taskTracker.swiftCompilerDidOutputMessage(message, targetName: parser.targetName)
//            self.updateProgress()
        }

        if let output = message.standardOutput {
            // first we want to print the output so users have it handy
            if !self.logLevel.isVerbose {
//                self.progressAnimation.clear()
            }

            self.outputStream.send(output)
            self.outputStream.flush()

            // next we want to try and scoop out any errors from the output (if reasonable size, otherwise this
            // will be very slow), so they can later be passed to the advice provider in case of failure.
            if output.utf8.count < 1024 * 10 {
                let regex = try! RegEx(pattern: #".*(error:[^\n]*)\n.*"#, options: .dotMatchesLineSeparators)
                for match in regex.matchGroups(in: output) {
                    self.errorMessagesByTarget[parser.targetName] = (
                        self.errorMessagesByTarget[parser.targetName] ?? []
                    ) + [match[0]]
                }
            }
        }

    }
    
    func swiftCompilerOutputParser(_ parser: Build.SwiftCompilerOutputParser, didFailWith error: any Error) {
        // TODO bp
        print("failed parsing with error: \(error.localizedDescription)")
    }
}

/// Parser for SwiftBuild output.
final class SwiftBuildSystemOutputParser {
//    typealias Message = SwiftBuildMessage
    private var buildSystem: SPMBuildCore.BuildSystem
//    private var parser: SwiftCompilerOutputParser?
    private let observabilityScope: ObservabilityScope
    private let outputStream: OutputByteStream
//    private let progressAnimation: ProgressAnimationProtocol
    private let logLevel: Basics.Diagnostic.Severity
    private var swiftOutputParser: SwiftCompilerOutputParser?
    private var errorMessagesByTarget: [String: [String]] = [:]

    public init(
        buildSystem: SPMBuildCore.BuildSystem,
        observabilityScope: ObservabilityScope,
        outputStream: OutputByteStream,
        logLevel: Basics.Diagnostic.Severity,
//        progressAnimation: ProgressAnimationProtocol
//        swiftOutputParser: SwiftCompilerOutputParser?
    )
    {
        self.buildSystem = buildSystem
        self.observabilityScope = observabilityScope
        self.outputStream = outputStream
        self.logLevel = logLevel
//        self.progressAnimation = progressAnimation
//        self.swiftOutputParser = swiftOutputParser
        self.swiftOutputParser = nil
        let outputParser: SwiftCompilerOutputParser? = { [weak self] in
            guard let self else { return nil }
                return .init(targetName: "", delegate: self)
        }()

        self.swiftOutputParser = outputParser
    }

    func parse(bytes data: Data) {
        swiftOutputParser?.parse(bytes: data)
    }

    func handleDiagnostic(_ diagnostic: SwiftBuildMessage.DiagnosticInfo) {
        let fixItsDescription = if diagnostic.fixIts.hasContent {
            ": " + diagnostic.fixIts.map { String(describing: $0) }.joined(separator: ", ")
        } else {
            ""
        }
        let message = if let locationDescription = diagnostic.location.userDescription {
            "\(locationDescription) \(diagnostic.message)\(fixItsDescription)"
        } else {
            "\(diagnostic.message)\(fixItsDescription)"
        }
        let severity: Diagnostic.Severity = switch diagnostic.kind {
        case .error: .error
        case .warning: .warning
        case .note: .info
        case .remark: .debug
        }
        self.observabilityScope.emit(severity: severity, message: "\(message)\n")

        for childDiagnostic in diagnostic.childDiagnostics {
            handleDiagnostic(childDiagnostic)
        }
    }

//    func swiftCompilerOutputParser(_ parser: Build.SwiftCompilerOutputParser, didParse message: Build.SwiftCompilerMessage) {
//        print("Attempting to parse output:")
//        print(parser.targetName)
//    }
//    
//    func swiftCompilerOutputParser(_ parser: Build.SwiftCompilerOutputParser, didFailWith error: any Error) {
//        print("Parser encountered error: \(error.localizedDescription)")
//    }
}

public final class SwiftBuildSystem: SPMBuildCore.BuildSystem {
    private let buildParameters: BuildParameters
    private let packageGraphLoader: () async throws -> ModulesGraph
    private let packageManagerResourcesDirectory: Basics.AbsolutePath?
    private let logLevel: Basics.Diagnostic.Severity
    private var packageGraph: AsyncThrowingValueMemoizer<ModulesGraph> = .init()
    private var pifBuilder: AsyncThrowingValueMemoizer<PIFBuilder> = .init()
    private let fileSystem: FileSystem
    private let observabilityScope: ObservabilityScope

    /// The output stream for the build delegate.
    private let outputStream: OutputByteStream

    /// The delegate used by the build system.
    public weak var delegate: SPMBuildCore.BuildSystemDelegate?

    /// A build message delegate to capture diagnostic output captured from the compiler.
    private var buildMessageParser: SwiftBuildSystemOutputParser?

    /// Configuration for building and invoking plugins.
    private let pluginConfiguration: PluginConfiguration

    /// Additional rules for different file types generated from plugins.
    private let additionalFileRules: [FileRuleDescription]

    public var builtTestProducts: [BuiltTestProduct] {
        get async {
            do {
                let graph = try await getPackageGraph()

                var builtProducts: [BuiltTestProduct] = []

                for package in graph.rootPackages {
                    for product in package.products where product.type == .test {
                        let binaryPath = try buildParameters.binaryPath(for: product)
                        builtProducts.append(
                            BuiltTestProduct(
                                productName: product.name,
                                binaryPath: binaryPath,
                                packagePath: package.path,
                                testEntryPointPath: product.underlying.testEntryPointPath
                            )
                        )
                    }
                }

                return builtProducts
            } catch {
                self.observabilityScope.emit(error)
                return []
            }
        }
    }

    public var buildPlan: SPMBuildCore.BuildPlan {
        get throws {
            throw StringError("Swift Build does not provide a build plan")
        }
    }

    public var hasIntegratedAPIDigesterSupport: Bool { true }

    public init(
        buildParameters: BuildParameters,
        packageGraphLoader: @escaping () async throws -> ModulesGraph,
        packageManagerResourcesDirectory: Basics.AbsolutePath?,
        additionalFileRules: [FileRuleDescription],
        outputStream: OutputByteStream,
        logLevel: Basics.Diagnostic.Severity,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope,
        pluginConfiguration: PluginConfiguration,
        delegate: BuildSystemDelegate?
    ) throws {
        self.buildParameters = buildParameters
        self.packageGraphLoader = packageGraphLoader
        self.packageManagerResourcesDirectory = packageManagerResourcesDirectory
        self.additionalFileRules = additionalFileRules
        self.outputStream = outputStream
        self.logLevel = logLevel
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "Swift Build System")
        self.pluginConfiguration = pluginConfiguration
        self.delegate = delegate //?? SWBOutputDelegate()
        self.buildMessageParser = .init(
            buildSystem: self,
            observabilityScope: observabilityScope,
            outputStream: outputStream,
            logLevel: logLevel
        )
    }

    private func createREPLArguments(
        session: SWBBuildServiceSession,
        request: SWBBuildRequest
    ) async throws -> CLIArguments {
        self.outputStream.send("Gathering repl arguments...")
        self.outputStream.flush()

        func getUniqueBuildSettingsIncludingDependencies(of targetGuid: [SWBConfiguredTarget], buildSettings: [String]) async throws -> Set<String> {
            let dependencyGraph = try await session.computeDependencyGraph(
                targetGUIDs: request.configuredTargets.map { SWBTargetGUID(rawValue: $0.guid)},
                buildParameters: request.parameters,
                includeImplicitDependencies: true,
            )
            var uniquePaths = Set<String>()
            for setting in buildSettings {
                self.outputStream.send(".")
                self.outputStream.flush()
                for (target, targetDependencies) in dependencyGraph {
                    for t in [target] + targetDependencies {
                        try await session.evaluateMacroAsStringList(
                            setting,
                            level: .target(t.rawValue),
                            buildParameters: request.parameters,
                            overrides: nil,
                        ).forEach({
                            uniquePaths.insert($0)
                        })
                    }
                }

            }
            return uniquePaths
        }

        // TODO: Need to determine how to get the inlude path of package system library dependencies
        let includePaths = try await getUniqueBuildSettingsIncludingDependencies(
            of: request.configuredTargets,
            buildSettings: [
                "BUILT_PRODUCTS_DIR",
                "HEADER_SEARCH_PATHS",
                "USER_HEADER_SEARCH_PATHS",
                "FRAMEWORK_SEARCH_PATHS",
            ]
        )

        let graph = try await self.getPackageGraph()
        // Link the special REPL product that contains all of the library targets.
        let replProductName: String = try graph.getReplProductName()

        // The graph should have the REPL product.
        assert(graph.product(for: replProductName) != nil)

        let arguments = ["repl", "-l\(replProductName)"] + includePaths.map {
            "-I\($0)"
        }

        self.outputStream.send("Done.\n")
        return arguments
    }

    private func supportedSwiftVersions() throws -> [SwiftLanguageVersion] {
        // Swift Build should support any of the supported language versions of SwiftPM and the rest of the toolchain
        SwiftLanguageVersion.supportedSwiftLanguageVersions
    }

    public func build(subset: BuildSubset, buildOutputs: [BuildOutput]) async throws -> BuildResult {
        // If any plugins are part of the build set, compile them now to surface
        // any errors up-front. Returns true if we should proceed with the build
        // or false if not. It will already have thrown any appropriate error.
        var result = BuildResult(
            serializedDiagnosticPathsByTargetName: .failure(StringError("Building was skipped")),
            replArguments: nil,
        )

        guard !buildParameters.shouldSkipBuilding else {
            result.serializedDiagnosticPathsByTargetName = .failure(StringError("Building was skipped"))
            return result
        }

        guard try await self.compilePlugins(in: subset) else {
            result.serializedDiagnosticPathsByTargetName = .failure(StringError("Plugin compilation failed"))
            return result
        }

        try await writePIF(buildParameters: buildParameters)

        return try await startSWBuildOperation(
            pifTargetName: subset.pifTargetName,
            buildOutputs: buildOutputs,
        )
    }

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

    /// Compiles any plugins specified or implied by the build subset, returning
    /// true if the build should proceed. Throws an error in case of failure. A
    /// reason why the build might not proceed even on success is if only plugins
    /// should be compiled.
    func compilePlugins(in subset: BuildSubset) async throws -> Bool {
        // Figure out what, if any, plugin descriptions to compile, and whether
        // to continue building after that based on the subset.
        let graph = try await getPackageGraph()

        /// Description for a plugin module. This is treated a bit differently from the
        /// regular kinds of modules, and is not included in the LLBuild description.
        /// But because the modules graph and build plan are not loaded for incremental
        /// builds, this information is included in the BuildDescription, and the plugin
        /// modules are compiled directly.
        struct PluginBuildDescription: Codable {
            /// The identity of the package in which the plugin is defined.
            public let package: PackageIdentity

            /// The name of the plugin module in that package (this is also the name of
            /// the plugin).
            public let moduleName: String

            /// The language-level module name.
            public let moduleC99Name: String

            /// The names of any plugin products in that package that vend the plugin
            /// to other packages.
            public let productNames: [String]

            /// The tools version of the package that declared the module. This affects
            /// the API that is available in the PackagePlugin module.
            public let toolsVersion: ToolsVersion

            /// Swift source files that comprise the plugin.
            public let sources: Sources

            /// Initialize a new plugin module description. The module is expected to be
            /// a `PluginTarget`.
            init(
                module: ResolvedModule,
                products: [ResolvedProduct],
                package: ResolvedPackage,
                toolsVersion: ToolsVersion,
                testDiscoveryTarget: Bool = false,
                fileSystem: FileSystem
            ) throws {
                guard module.underlying is PluginModule else {
                    throw InternalError("underlying target type mismatch \(module)")
                }

                self.package = package.identity
                self.moduleName = module.name
                self.moduleC99Name = module.c99name
                self.productNames = products.map(\.name)
                self.toolsVersion = toolsVersion
                self.sources = module.sources
            }
        }

        var allPlugins: [PluginBuildDescription] = []

        for pluginModule in graph.allModules.filter({ ($0.underlying as? PluginModule) != nil }) {
            guard let package = graph.package(for: pluginModule) else {
                throw InternalError("Package not found for module: \(pluginModule.name)")
            }

            let toolsVersion = package.manifest.toolsVersion

            let pluginProducts = package.products.filter { $0.modules.contains(id: pluginModule.id) }

            allPlugins.append(try PluginBuildDescription(
                module: pluginModule,
                products: pluginProducts,
                package: package,
                toolsVersion: toolsVersion,
                fileSystem: fileSystem
            ))
        }

        let pluginsToCompile: [PluginBuildDescription]
        let continueBuilding: Bool
        switch subset {
        case .allExcludingTests, .allIncludingTests:
            pluginsToCompile = allPlugins
            continueBuilding = true
        case .product(let productName, _):
            pluginsToCompile = allPlugins.filter{ $0.productNames.contains(productName) }
            continueBuilding = pluginsToCompile.isEmpty
        case .target(let targetName, _):
            pluginsToCompile = allPlugins.filter{ $0.moduleName == targetName }
            continueBuilding = pluginsToCompile.isEmpty
        }

        final class Delegate: PluginScriptCompilerDelegate {
            var failed: Bool = false
            var observabilityScope: ObservabilityScope

            public init(observabilityScope: ObservabilityScope) {
                self.observabilityScope = observabilityScope
            }

            func willCompilePlugin(commandLine: [String], environment: [String: String]) { }

            func didCompilePlugin(result: PluginCompilationResult) {
                if !result.compilerOutput.isEmpty && !result.succeeded {
                    print(result.compilerOutput, to: &stdoutStream)
                } else if !result.compilerOutput.isEmpty {
                    observabilityScope.emit(info: result.compilerOutput)
                }

                failed = !result.succeeded
            }

            func skippedCompilingPlugin(cachedResult: PluginCompilationResult) { }
        }

        // Compile any plugins we ended up with. If any of them fails, it will
        // throw.
        for plugin in pluginsToCompile {
            let delegate = Delegate(observabilityScope: observabilityScope)

            _ = try await self.pluginConfiguration.scriptRunner.compilePluginScript(
                sourceFiles: plugin.sources.paths,
                pluginName: plugin.moduleName,
                toolsVersion: plugin.toolsVersion,
                observabilityScope: observabilityScope,
                callbackQueue: DispatchQueue.sharedConcurrent,
                delegate: delegate
            )

            if delegate.failed {
                throw Diagnostics.fatalError
            }
        }

        // If we get this far they all succeeded. Return whether to continue the
        // build, based on the subset.
        return continueBuilding
    }

    private func startSWBuildOperation(
        pifTargetName: String,
        buildOutputs: [BuildOutput]
    ) async throws -> BuildResult {
        let buildStartTime = ContinuousClock.Instant.now
        var symbolGraphOptions: BuildOutput.SymbolGraphOptions?
        for output in buildOutputs {
            switch output {
            case .symbolGraph(let options):
                symbolGraphOptions = options
            default:
                continue
            }
        }

        // TODO bp create swiftcompileroutputparser here?
//        self.buildMessageParser = .init(
//            buildSystem: self,
//            observabilityScope: self.observabilityScope,
//            outputStream: self.outputStream,
//            logLevel: self.logLevel
//        //                progressAnimation: progressAnimation
//        )
//        let parser = SwiftCompilerOutputParser(targetName: pifTargetName, delegate: self.delegate)
        // TODO bp: see BuildOperation, and where LLBuildTracker is created and used.

        var replArguments: CLIArguments?
        var artifacts: [(String, PluginInvocationBuildResult.BuiltArtifact)]?
        return try await withService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)) { service in
            let derivedDataPath = self.buildParameters.dataPath

            let progressAnimation = ProgressAnimation.ninja(
                stream: self.outputStream,
                verbose: self.logLevel.isVerbose
            )

            var serializedDiagnosticPathsByTargetName: [String: [Basics.AbsolutePath]] = [:]
            do {
                try await withSession(service: service, name: self.buildParameters.pifManifest.pathString, toolchainPath: self.buildParameters.toolchain.toolchainDir, packageManagerResourcesDirectory: self.packageManagerResourcesDirectory) { session, _ in
                    self.outputStream.send("Building for \(self.buildParameters.configuration == .debug ? "debugging" : "production")...\n")

                    // Load the workspace, and set the system information to the default
                    do {
                        try await session.loadWorkspace(containerPath: self.buildParameters.pifManifest.pathString)
                        try await session.setSystemInfo(.default())
                    } catch {
                        self.observabilityScope.emit(error: error.localizedDescription)
                        throw error
                    }

                    // Find the targets to build.
                    let configuredTargets: [SWBTargetGUID]
                    do {
                        let workspaceInfo = try await session.workspaceInfo()

                        configuredTargets = try [pifTargetName].map { targetName in
                            // TODO we filter dynamic targets until Swift Build doesn't give them to us anymore
                            let infos = workspaceInfo.targetInfos.filter { $0.targetName == targetName && !TargetSuffix.dynamic.hasSuffix(id: GUID($0.guid)) }
                            switch infos.count {
                            case 0:
                                self.observabilityScope.emit(error: "Could not find target named '\(targetName)'")
                                throw Diagnostics.fatalError
                            case 1:
                                return SWBTargetGUID(rawValue: infos[0].guid)
                            default:
                                self.observabilityScope.emit(error: "Found multiple targets named '\(targetName)'")
                                throw Diagnostics.fatalError
                            }
                        }
                    } catch {
                        self.observabilityScope.emit(error: error.localizedDescription)
                        throw error
                    }

//                    for target in configuredTargets {
//                        let outputParser = SwiftBuildSystemOutputParser(
//                            buildSystem: self,
//                            observabilityScope:self.observabilityScope,
//                            outputStream: self.outputStream,
//                            logLevel: self.logLevel,
//                            progressAnimation: progressAnimation,
//                            swiftOutputParser: .init(
//                                targetName: target,
//                                delegate: self)
//                            )
//                    }

                    let request = try await self.makeBuildRequest(session: session, configuredTargets: configuredTargets, derivedDataPath: derivedDataPath, symbolGraphOptions: symbolGraphOptions)

                    struct BuildState {
                        private var targetsByID: [Int: SwiftBuild.SwiftBuildMessage.TargetStartedInfo] = [:]
                        private var activeTasks: [Int: SwiftBuild.SwiftBuildMessage.TaskStartedInfo] = [:]

                        mutating func started(task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws {
                            if activeTasks[task.taskID] != nil {
                                throw Diagnostics.fatalError
                            }
                            activeTasks[task.taskID] = task
                        }

                        mutating func completed(task: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo) throws -> SwiftBuild.SwiftBuildMessage.TaskStartedInfo {
                            guard let task = activeTasks[task.taskID] else {
                                throw Diagnostics.fatalError
                            }
                            return task
                        }

                        mutating func started(target: SwiftBuild.SwiftBuildMessage.TargetStartedInfo) throws {
                            if targetsByID[target.targetID] != nil {
                                throw Diagnostics.fatalError
                            }
                            targetsByID[target.targetID] = target
                        }

                        mutating func target(for task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws -> SwiftBuild.SwiftBuildMessage.TargetStartedInfo? {
                            guard let id = task.targetID else {
                                return nil
                            }
                            guard let target = targetsByID[id] else {
                                throw Diagnostics.fatalError
                            }
                            return target
                        }
                    }

                    func emitEvent(_ message: SwiftBuild.SwiftBuildMessage, buildState: inout BuildState) throws {
                        guard !self.logLevel.isQuiet else { return }
                        switch message {
                        case .buildCompleted(let info):
                            progressAnimation.complete(success: info.result == .ok)
                            if info.result == .cancelled {
                                self.delegate?.buildSystemDidCancel(self)
                            } else {
                                self.delegate?.buildSystem(self, didFinishWithResult: info.result == .ok)
                            }
                        case .didUpdateProgress(let progressInfo):
                            var step = Int(progressInfo.percentComplete)
                            if step < 0 { step = 0 }
                            let message = if let targetName = progressInfo.targetName {
                                "\(targetName) \(progressInfo.message)"
                            } else {
                                "\(progressInfo.message)"
                            }
                            progressAnimation.update(step: step, total: 100, text: message)
                            self.delegate?.buildSystem(self, didUpdateTaskProgress: message)
                        case .diagnostic(let info):
                            func emitInfoAsDiagnostic(info: SwiftBuildMessage.DiagnosticInfo) {
                                let fixItsDescription = if info.fixIts.hasContent {
                                    ": " + info.fixIts.map { String(describing: $0) }.joined(separator: ", ")
                                } else {
                                    ""
                                }
                                let message = if let locationDescription = info.location.userDescription {
                                    "\(locationDescription) \(info.message)\(fixItsDescription)"
                                } else {
                                    "\(info.message)\(fixItsDescription)"
                                }
                                let severity: Diagnostic.Severity = switch info.kind {
                                case .error: .error
                                case .warning: .warning
                                case .note: .info
                                case .remark: .debug
                                }
                                self.observabilityScope.emit(severity: severity, message: "\(message)\n")

                                for childDiagnostic in info.childDiagnostics {
                                    emitInfoAsDiagnostic(info: childDiagnostic)
                                }
                            }

                            emitInfoAsDiagnostic(info: info)
                        case .output(let info):
//                            let parsedOutputText = self.parseOutput(info)
                            self.observabilityScope.emit(info: "\(String(decoding: info.data, as: UTF8.self))")
                        case .taskStarted(let info):
                            try buildState.started(task: info)

                            if let commandLineDisplay = info.commandLineDisplayString {
                                self.observabilityScope.emit(info: "\(info.executionDescription)\n\(commandLineDisplay)")
                            } else {
                                self.observabilityScope.emit(info: "\(info.executionDescription)")
                            }

                            if self.logLevel.isVerbose {
                                if let commandLineDisplay = info.commandLineDisplayString {
                                    self.outputStream.send("\(info.executionDescription)\n\(commandLineDisplay)")
                                } else {
                                    self.outputStream.send("\(info.executionDescription)")
                                }
                            }
                            let targetInfo = try buildState.target(for: info)
                            self.delegate?.buildSystem(self, willStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
                            self.delegate?.buildSystem(self, didStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
                        case .taskComplete(let info):
                            let startedInfo = try buildState.completed(task: info)
                            if info.result != .success {
                                self.observabilityScope.emit(severity: .error, message: "\(startedInfo.ruleInfo) failed with a nonzero exit code. Command line: \(startedInfo.commandLineDisplayString ?? "<no command line>")")
                            }
                            let targetInfo = try buildState.target(for: startedInfo)
                            self.delegate?.buildSystem(self, didFinishCommand: BuildSystemCommand(startedInfo, targetInfo: targetInfo))
                            if let targetName = targetInfo?.targetName {
                                serializedDiagnosticPathsByTargetName[targetName, default: []].append(contentsOf: startedInfo.serializedDiagnosticsPaths.compactMap {
                                    try? Basics.AbsolutePath(validating: $0.pathString)
                                })
                            }
                        case .targetStarted(let info):
                            try buildState.started(target: info)
                        case .planningOperationStarted, .planningOperationCompleted, .reportBuildDescription, .reportPathMap, .preparedForIndex, .backtraceFrame, .buildStarted, .preparationComplete, .targetUpToDate, .targetComplete, .taskUpToDate:
                            break
                        case .buildDiagnostic, .targetDiagnostic, .taskDiagnostic:
                            break // deprecated
                        case .buildOutput, .targetOutput, .taskOutput:
                            break // deprecated
                        @unknown default:
                            break
                        }
                    }

                    let operation = try await session.createBuildOperation(
                        request: request,
                        delegate: PlanningOperationDelegate(), // TODO bp possibly enhance this delegate?
                        retainBuildDescription: true
                    )

                    var buildDescriptionID: SWBBuildDescriptionID? = nil
                    var buildState = BuildState()
                    for try await event in try await operation.start() {
                        if case .reportBuildDescription(let info) = event {
                            if buildDescriptionID != nil {
                                self.observabilityScope.emit(debug: "build unexpectedly reported multiple build description IDs")
                            }
                            buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
                        }
                        try emitEvent(event, buildState: &buildState)
                    }

                    await operation.waitForCompletion()

                    switch operation.state {
                    case .succeeded:
                        guard !self.logLevel.isQuiet else { return }
                        progressAnimation.update(step: 100, total: 100, text: "")
                        progressAnimation.complete(success: true)
                        let duration = ContinuousClock.Instant.now - buildStartTime
                        let formattedDuration = duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2, rounded: .up)))
                        self.outputStream.send("Build complete! (\(formattedDuration))\n")
                        self.outputStream.flush()
                    case .failed:
                        self.observabilityScope.emit(error: "Build failed")
                        throw Diagnostics.fatalError
                    case .cancelled:
                        self.observabilityScope.emit(error: "Build was cancelled")
                        throw Diagnostics.fatalError
                    case .requested, .running, .aborted:
                        self.observabilityScope.emit(error: "Unexpected build state")
                        throw Diagnostics.fatalError
                    }

                    if buildOutputs.contains(.replArguments) {
                        replArguments = try await self.createREPLArguments(session: session, request: request)
                    }

                    if buildOutputs.contains(.builtArtifacts) {
                        if let buildDescriptionID {
                            let targetInfo = try await session.configuredTargets(buildDescription: buildDescriptionID, buildRequest: request)
                            artifacts = targetInfo.compactMap { target in
                                guard let artifactInfo = target.artifactInfo else {
                                    return nil
                                }
                                let kind: PluginInvocationBuildResult.BuiltArtifact.Kind = switch artifactInfo.kind {
                                case .executable:
                                    .executable
                                case .staticLibrary:
                                    .staticLibrary
                                case .dynamicLibrary:
                                    .dynamicLibrary
                                case .framework:
                                    // We treat frameworks as dylibs here, but the plugin API should grow to accomodate more product types
                                    .dynamicLibrary
                                }
                                var name = target.name
                                // FIXME: We need a better way to map between SwiftPM target/product names and PIF target names
                                if pifTargetName.hasSuffix("-product") {
                                    name = String(name.dropLast(8))
                                }
                                return (name, .init(
                                    path: artifactInfo.path,
                                    kind: kind
                                ))
                            }
                        } else {
                            self.observabilityScope.emit(error: "failed to compute built artifacts list")
                        }
                    }

                    if let buildDescriptionID {
                        await session.releaseBuildDescription(id: buildDescriptionID)
                    }
                }
            } catch let sessError as SessionFailedError {
                for diagnostic in sessError.diagnostics {
                    self.observabilityScope.emit(error: diagnostic.message)
                }
                throw sessError.error
            } catch {
                throw error
            }

            return BuildResult(
                serializedDiagnosticPathsByTargetName: .success(serializedDiagnosticPathsByTargetName),
                symbolGraph: SymbolGraphResult(
                    outputLocationForTarget: { target, buildParameters in
                        return ["\(buildParameters.triple.archName)", "\(target).symbolgraphs"]
                    }
                ),
                replArguments: replArguments,
                builtArtifacts: artifacts
            )
        }
    }

    private func parseOutput(_ info: SwiftBuildMessage.OutputInfo) -> String {
        var result = ""
        let data = info.data
        // let parser = SwiftCompilerOutputParser()
        // use json parser to parse bytes
//        self.buildMessageParser?.parse(bytes: data)

        return result
    }

    private func makeRunDestination() -> SwiftBuild.SWBRunDestinationInfo {
        let platformName: String
        let sdkName: String
        if self.buildParameters.triple.isAndroid() {
            // Android triples are identified by the environment part of the triple
            platformName = "android"
            sdkName = platformName
        } else if self.buildParameters.triple.isWasm {
            // Swift Build uses webassembly instead of wasi as the platform name
            platformName = "webassembly"
            sdkName = platformName
        } else {
            platformName = self.buildParameters.triple.darwinPlatform?.platformName ?? self.buildParameters.triple.osNameUnversioned
            sdkName = platformName
        }

        let sdkVariant: String?
        if self.buildParameters.triple.environment == .macabi {
            sdkVariant = "iosmac"
        } else {
            sdkVariant = nil
        }

        return SwiftBuild.SWBRunDestinationInfo(
            platform: platformName,
            sdk: sdkName,
            sdkVariant: sdkVariant,
            targetArchitecture: buildParameters.triple.archName,
            supportedArchitectures: [],
            disableOnlyActiveArch: (buildParameters.architectures?.count ?? 1) > 1
        )
    }

    private func makeBuildParameters(session: SWBBuildServiceSession, symbolGraphOptions: BuildOutput.SymbolGraphOptions?) async throws -> SwiftBuild.SWBBuildParameters {
        // Generate the run destination parameters.
        let runDestination = makeRunDestination()

        var verboseFlag: [String] = []
        if self.logLevel == .debug {
            verboseFlag = ["-v"] // Clang's verbose flag
        }

        // Generate a table of any overriding build settings.
        var settings: [String: String] = [:]

        // If the SwiftPM toolchain corresponds to a toolchain registered with the lower level build system, add it to the toolchain stack.
        // Otherwise, apply overrides for each component of the SwiftPM toolchain.
        if let toolchainID = try await session.lookupToolchain(at: buildParameters.toolchain.toolchainDir.pathString) {
            settings["TOOLCHAINS"] = "\(toolchainID.rawValue) $(inherited)"
        } else {
            // FIXME: This list of overrides is incomplete.
            // An error with determining the override should not be fatal here.
            settings["CC"] = try? buildParameters.toolchain.getClangCompiler().pathString
            // Always specify the path of the effective Swift compiler, which was determined in the same way as for the
            // native build system.
            settings["SWIFT_EXEC"] = buildParameters.toolchain.swiftCompilerPath.pathString
        }

        // FIXME: workaround for old Xcode installations such as what is in CI
        settings["LM_SKIP_METADATA_EXTRACTION"] = "YES"
        if let symbolGraphOptions {
            settings["RUN_SYMBOL_GRAPH_EXTRACT"] = "YES"

            if symbolGraphOptions.prettyPrint {
                settings["DOCC_PRETTY_PRINT"] = "YES"
            }

            if symbolGraphOptions.emitExtensionBlocks {
                settings["DOCC_EXTRACT_EXTENSION_SYMBOLS"] = "YES"
            }

            if !symbolGraphOptions.includeInheritedDocs {
                settings["DOCC_SKIP_INHERITED_DOCS"] = "YES"
            }

            if !symbolGraphOptions.includeSynthesized {
                settings["DOCC_SKIP_SYNTHESIZED_MEMBERS"] = "YES"
            }

            if symbolGraphOptions.includeSPI {
                settings["DOCC_EXTRACT_SPI_DOCUMENTATION"] = "YES"
            }

            switch symbolGraphOptions.minimumAccessLevel {
            case .private:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "private"
            case .fileprivate:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "fileprivate"
            case .internal:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "internal"
            case .package:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "package"
            case .public:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "public"
            case .open:
                settings["DOCC_MINIMUM_ACCESS_LEVEL"] = "open"
            }
        }

        let normalizedTriple = Triple(buildParameters.triple.triple, normalizing: true)
        if let deploymentTargetSettingName = normalizedTriple.deploymentTargetSettingName {
            let value = normalizedTriple.deploymentTargetVersion

            // Only override the deployment target if a version is explicitly specified;
            // for Apple platforms this normally comes from the package manifest and may
            // not be set to the same value for all packages in the package graph.
            if value != .zero {
                settings[deploymentTargetSettingName] = value.description
            }
        }

        // FIXME: "none" triples get a placeholder SDK/platform and don't support any specific triple by default. Unlike most platforms, where the vendor and environment is implied as a function of the arch and "platform", bare metal operates in terms of triples directly. We need to replace this bringup convenience with a more idiomatic mechanism, perhaps in the build request.
        if buildParameters.triple.os == .noneOS {
            settings["ARCHS"] = buildParameters.triple.archName
            settings["VALID_ARCHS"] = buildParameters.triple.archName
            settings["LLVM_TARGET_TRIPLE_VENDOR"] = buildParameters.triple.vendorName
            if !buildParameters.triple.environmentName.isEmpty {
                settings["LLVM_TARGET_TRIPLE_SUFFIX"] = "-" + buildParameters.triple.environmentName
            }
        }

        settings["LIBRARY_SEARCH_PATHS"] = try "$(inherited) \(buildParameters.toolchain.toolchainLibDir.pathString)"
        settings["OTHER_CFLAGS"] = (
            verboseFlag +
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.cCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.cCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")
        settings["OTHER_CPLUSPLUSFLAGS"] = (
            verboseFlag +
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.cxxCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.cxxCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")
        settings["OTHER_SWIFT_FLAGS"] = (
            verboseFlag +
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.swiftCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.swiftCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")

        // TODO bp passing -v flag via verboseFlag here; investigate linker messages
        settings["OTHER_LDFLAGS"] = (
            verboseFlag + // clang will be invoked to link so the verbose flag is valid for it
                ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.linkerFlags.asSwiftcLinkerFlags().map { $0.shellEscaped() }
                + buildParameters.flags.linkerFlags.asSwiftcLinkerFlags().map { $0.shellEscaped() }
        ).joined(separator: " ")

        // Optionally also set the list of architectures to build for.
        if let architectures = buildParameters.architectures, !architectures.isEmpty {
            settings["ARCHS"] = architectures.joined(separator: " ")
        }

        // When building with the CLI for macOS, test bundles should generate entrypoints for compatibility with swiftpm-testing-helper.
        if buildParameters.triple.isMacOSX {
            settings["GENERATE_TEST_ENTRYPOINTS_FOR_BUNDLES"] = "YES"
        }

        func reportConflict(_ a: String, _ b: String) throws -> String {
            throw StringError("Build parameters constructed conflicting settings overrides '\(a)' and '\(b)'")
        }
        try settings.merge(Self.constructDebuggingSettingsOverrides(from: buildParameters.debuggingParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructDriverSettingsOverrides(from: buildParameters.driverParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructLinkerSettingsOverrides(from: buildParameters.linkingParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructTestingSettingsOverrides(from: buildParameters.testingParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructAPIDigesterSettingsOverrides(from: buildParameters.apiDigesterMode), uniquingKeysWith: reportConflict)

        // Generate the build parameters.
        var params = SwiftBuild.SWBBuildParameters()
        params.configurationName = buildParameters.configuration.swiftbuildName
        var overridesSynthesized = SwiftBuild.SWBSettingsTable()
        for (key, value) in settings {
            overridesSynthesized.set(value: value, for: key)
        }
        params.overrides.synthesized = overridesSynthesized
        params.activeRunDestination = runDestination

        return params
    }

    public func makeBuildRequest(session: SWBBuildServiceSession, configuredTargets: [SWBTargetGUID], derivedDataPath: Basics.AbsolutePath, symbolGraphOptions: BuildOutput.SymbolGraphOptions?) async throws -> SWBBuildRequest {
        var request = SWBBuildRequest()
        request.parameters = try await makeBuildParameters(session: session, symbolGraphOptions: symbolGraphOptions)
        request.configuredTargets = configuredTargets.map { SWBConfiguredTarget(guid: $0.rawValue, parameters: request.parameters) }
        request.useParallelTargets = true
        request.useImplicitDependencies = false
        request.useDryRun = false
        request.hideShellScriptEnvironment = true
        request.showNonLoggedProgress = true

        // Override the arena. We need to apply the arena info to both the request-global build
        // parameters as well as the target-specific build parameters, since they may have been
        // deserialized from the build request file above overwriting the build parameters we set
        // up earlier in this method.

        #if os(Windows)
        let ddPathPrefix = derivedDataPath.pathString.replacingOccurrences(of: "\\", with: "/")
        #else
        let ddPathPrefix = derivedDataPath.pathString
        #endif

        let arenaInfo = SWBArenaInfo(
            derivedDataPath: ddPathPrefix,
            buildProductsPath: ddPathPrefix + "/Products",
            buildIntermediatesPath: ddPathPrefix + "/Intermediates.noindex",
            pchPath: ddPathPrefix + "/PCH",
            indexRegularBuildProductsPath: nil,
            indexRegularBuildIntermediatesPath: nil,
            indexPCHPath: ddPathPrefix,
            indexDataStoreFolderPath: ddPathPrefix,
            indexEnableDataStore: request.parameters.arenaInfo?.indexEnableDataStore ?? false
        )

        request.parameters.arenaInfo = arenaInfo
        request.configuredTargets = request.configuredTargets.map { configuredTarget in
            var configuredTarget = configuredTarget
            configuredTarget.parameters?.arenaInfo = arenaInfo
            return configuredTarget
        }

        return request
    }

    private static func constructDebuggingSettingsOverrides(from parameters: BuildParameters.Debugging) -> [String: String] {
        var settings: [String: String] = [:]
        // TODO: debugInfoFormat: https://github.com/swiftlang/swift-build/issues/560
        // TODO: shouldEnableDebuggingEntitlement: Enable/Disable get-task-allow
        // TODO: omitFramePointer: https://github.com/swiftlang/swift-build/issues/561
        return settings
    }

    private static func constructDriverSettingsOverrides(from parameters: BuildParameters.Driver) -> [String: String] {
        var settings: [String: String] = [:]
        switch parameters.explicitTargetDependencyImportCheckingMode {
        case .none:
            break
        case .warn:
            settings["DIAGNOSE_MISSING_TARGET_DEPENDENCIES"] = "YES"
        case .error:
            settings["DIAGNOSE_MISSING_TARGET_DEPENDENCIES"] = "YES_ERROR"
        }

        if parameters.enableParseableModuleInterfaces {
            settings["SWIFT_EMIT_MODULE_INTERFACE"] = "YES"
        }

        return settings
    }

    private static func constructLinkerSettingsOverrides(from parameters: BuildParameters.Linking) -> [String: String] {
        var settings: [String: String] = [:]

        if parameters.linkerDeadStrip {
            settings["DEAD_CODE_STRIPPING"] = "YES"
        }

        switch parameters.linkTimeOptimizationMode {
        case .full:
            settings["LLVM_LTO"] = "YES"
            settings["SWIFT_LTO"] = "YES"
        case .thin:
            settings["LLVM_LTO"] = "YES_THIN"
            settings["SWIFT_LTO"] = "YES_THIN"
        case nil:
            break
        }

        // TODO: shouldDisableLocalRpath
        // TODO: shouldLinkStaticSwiftStdlib

        return settings
    }

    private static func constructTestingSettingsOverrides(from parameters: BuildParameters.Testing) -> [String: String] {
        var settings: [String: String] = [:]

        // Coverage settings
        settings["CLANG_COVERAGE_MAPPING"] = parameters.enableCodeCoverage ? "YES" : "NO"

        switch parameters.explicitlyEnabledTestability {
        case true:
            settings["ENABLE_TESTABILITY"] = "YES"
        case false:
            settings["ENABLE_TESTABILITY"] = "NO"
        default:
            break
        }

        // TODO: experimentalTestOutput
        // TODO: explicitlyEnabledDiscovery
        // TODO: explicitlySpecifiedPath

        return settings
    }

    private static func constructAPIDigesterSettingsOverrides(from digesterMode: BuildParameters.APIDigesterMode?) -> [String: String] {
        var settings: [String: String] = [:]
        switch digesterMode {
        case .generateBaselines(let baselinesDirectory, let modulesRequestingBaselines):
            settings["SWIFT_API_DIGESTER_MODE"] = "api"
            for module in modulesRequestingBaselines {
                settings["RUN_SWIFT_ABI_GENERATION_TOOL_MODULE_\(module)"] = "YES"
            }
            settings["RUN_SWIFT_ABI_GENERATION_TOOL"] = "$(RUN_SWIFT_ABI_GENERATION_TOOL_MODULE_$(PRODUCT_MODULE_NAME))"
            settings["SWIFT_ABI_GENERATION_TOOL_OUTPUT_DIR"] = baselinesDirectory.appending(components: ["$(PRODUCT_MODULE_NAME)", "ABI"]).pathString
        case .compareToBaselines(let baselinesDirectory, let modulesToCompare, let breakageAllowListPath):
            settings["SWIFT_API_DIGESTER_MODE"] = "api"
            settings["SWIFT_ABI_CHECKER_DOWNGRADE_ERRORS"] = "YES"
            for module in modulesToCompare {
                settings["RUN_SWIFT_ABI_CHECKER_TOOL_MODULE_\(module)"] = "YES"
            }
            settings["RUN_SWIFT_ABI_CHECKER_TOOL"] = "$(RUN_SWIFT_ABI_CHECKER_TOOL_MODULE_$(PRODUCT_MODULE_NAME))"
            settings["SWIFT_ABI_CHECKER_BASELINE_DIR"] = baselinesDirectory.appending(component: "$(PRODUCT_MODULE_NAME)").pathString
            if let breakageAllowListPath {
                settings["SWIFT_ABI_CHECKER_EXCEPTIONS_FILE"] = breakageAllowListPath.pathString
            }
        case nil:
            break
        }
        return settings
    }

    private func getPIFBuilder() async throws -> PIFBuilder {
        try await pifBuilder.memoize {
            let graph = try await getPackageGraph()
            let pifBuilder = try PIFBuilder(
                graph: graph,
                parameters: .init(
                    buildParameters,
                    supportedSwiftVersions: supportedSwiftVersions(),
                    pluginScriptRunner: self.pluginConfiguration.scriptRunner,
                    disableSandbox: self.pluginConfiguration.disableSandbox,
                    pluginWorkingDirectory: self.pluginConfiguration.workDirectory,
                    additionalFileRules: additionalFileRules
                ),
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope,
            )
            return pifBuilder
        }
    }

    public func generatePIF(preserveStructure: Bool) async throws -> String {
        return try await getPIFBuilder().generatePIF(
            preservePIFModelStructure: preserveStructure,
            printPIFManifestGraphviz: buildParameters.printPIFManifestGraphviz,
            buildParameters: buildParameters
        )
    }

    public func writePIF(buildParameters: BuildParameters) async throws {
        let pif = try await generatePIF(preserveStructure: false)
        try self.fileSystem.writeIfChanged(path: buildParameters.pifManifest, string: pif)
    }

    public func cancel(deadline: DispatchTime) throws {}

    /// Returns the package graph using the graph loader closure.
    ///
    /// First access will cache the graph.
    public func getPackageGraph() async throws -> ModulesGraph {
        try await packageGraph.memoize {
            try await packageGraphLoader()
        }
    }
}

// MARK: - Helpers

extension String {
    /// Escape the usual shell related things, such as quoting, but also handle Windows
    /// back-slashes.
    fileprivate func shellEscaped() -> String {
        #if os(Windows)
        return self.spm_shellEscaped().replacingOccurrences(of: "\\", with: "/")
        #else
        return self.spm_shellEscaped()
        #endif
    }
}

fileprivate extension SwiftBuild.SwiftBuildMessage.DiagnosticInfo.Location {
    var userDescription: String? {
        switch self {
        case .path(let path, let fileLocation):
            switch fileLocation {
            case .textual(let line, let column):
                var description = "\(path):\(line)"
                if let column { description += ":\(column)" }
                return description
            case .object(let identifier):
                return "\(path):\(identifier)"
            case .none:
                return path
            }
        
        case .buildSettings(let names):
            return names.joined(separator: ", ")
        
        case .buildFiles(let buildFiles, let targetGUID):
            return "\(targetGUID): " + buildFiles.map { String(describing: $0) }.joined(separator: ", ")
            
        case .unknown:
            return nil
        }
    }
}

fileprivate extension BuildSystemCommand {
    init(_ taskStartedInfo: SwiftBuildMessage.TaskStartedInfo, targetInfo: SwiftBuildMessage.TargetStartedInfo?) {
        self = .init(
            name: taskStartedInfo.executionDescription,
            targetName: targetInfo?.targetName,
            description: taskStartedInfo.commandLineDisplayString ?? "",
            serializedDiagnosticPaths: taskStartedInfo.serializedDiagnosticsPaths.compactMap {
                try? Basics.AbsolutePath(validating: $0.pathString)
            }
        )
    }
}

fileprivate extension Triple {
    var deploymentTargetSettingName: String? {
        switch (self.os, self.environment) {
        case (.macosx, _):
            return "MACOSX_DEPLOYMENT_TARGET"
        case (.ios, _):
            return "IPHONEOS_DEPLOYMENT_TARGET"
        case (.tvos, _):
            return "TVOS_DEPLOYMENT_TARGET"
        case (.watchos, _):
            return "WATCHOS_DEPLOYMENT_TARGET"
        case (_, .android):
            return "ANDROID_DEPLOYMENT_TARGET"
        default:
            return nil
        }
    }

    var deploymentTargetVersion: Version {
        if isAndroid() {
            // Android triples store the version in the environment
            var environmentName = self.environmentName[...]
            if environment != nil {
                let prefixes = ["androideabi", "android"]
                for prefix in prefixes {
                    if environmentName.hasPrefix(prefix) {
                        environmentName = environmentName.dropFirst(prefix.count)
                        break
                    }
                }
            }

            return Version(parse: environmentName)
        }
        return osVersion
    }
}
