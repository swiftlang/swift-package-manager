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

import var TSCBasic.stdoutStream

import Foundation
import SWBBuildService
import SwiftBuild
import enum SWBCore.SwiftAPIDigesterMode
import struct SWBUtil.XcodeVersionInfo
import struct SWBUtil.Path

struct SessionFailedError: Error {
    var error: Error
    var diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
}

package func withService<T>(
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

/// Determines the effective toolchain path and whether it is embedded in an Xcode installation.
///
/// On Windows, the "developer dir" is two levels up from the toolchain dir, unlike Swift.org
/// toolchains on other platforms where they are both the same.
///
/// Users often rename Xcode.app, and in Swift.org CI on macOS we construct the toolchain under
/// a nonfunctioning shell of Xcode.app. Instead of just checking the app name, see if we can
/// find the app's version.plist at the expected location.
func toolchainDeveloperPathInfo(toolchain: Toolchain) throws -> (toolchainPath: Basics.AbsolutePath, isEmbeddedInXcode: Bool) {
    let toolchainPath = try toolchain.toolchainDir

    // On Windows, the "developer dir" is two levels up from the toolchain dir,
    // unlike Swift.org toolchains on other platforms where they are both the same.
    if ProcessInfo.hostOperatingSystem == .windows {
        return (toolchainPath.parentDirectory.parentDirectory, false)
    }

    let xcodeVersionPlistPath = toolchainPath
        .parentDirectory // Remove 'XcodeDefault.xctoolchain'
        .parentDirectory // Remove 'Toolchains'
        .parentDirectory // Remove 'Developer'
        .appending(component: "version.plist")
    let isEmbeddedInXcode = (try? XcodeVersionInfo.versionInfo(versionPath: SWBUtil.Path(xcodeVersionPlistPath.pathString))) != nil
    return (toolchainPath, isEmbeddedInXcode)
}

public func createSession(
    service: SWBBuildService,
    name: String,
    toolchain: Toolchain,
    packageManagerResourcesDirectory: Basics.AbsolutePath?
) async throws-> (SWBBuildServiceSession, [SwiftBuildMessage.DiagnosticInfo]) {

    var buildSessionEnv: [String: String]? = nil
    if let metalToolchainPath = toolchain.metalToolchainPath {
        buildSessionEnv = ["EXTERNAL_TOOLCHAINS_DIR": metalToolchainPath.pathString]
    }
    let (toolchainPath, toolchainIsEmbeddedInXcode) = try toolchainDeveloperPathInfo(toolchain: toolchain)

    // SWIFT_EXEC and SWIFT_EXEC_MANIFEST may need to be overridden in debug scenarios in order to pick up Open Source toolchains
    let sessionResult = if toolchainIsEmbeddedInXcode {
        // If this toolchain is bundled with Xcode.app, let the build service handle toolchain registration.
        await service.createSession(name: name, developerPath: nil, resourceSearchPaths: packageManagerResourcesDirectory.map { [$0.pathString] } ?? [], cachePath: nil, inferiorProductsPath: nil, environment: buildSessionEnv)
    } else {
        // Otherwise, treat this toolchain as standalone when initializing the build service.
        await service.createSession(name: name, swiftToolchainPath: toolchainPath.pathString, resourceSearchPaths: packageManagerResourcesDirectory.map { [$0.pathString] } ?? [], cachePath: nil, inferiorProductsPath: nil, environment: buildSessionEnv)
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
    toolchain: Toolchain,
    packageManagerResourcesDirectory: Basics.AbsolutePath?,
    body: @escaping (
        _ session: SWBBuildServiceSession,
        _ diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
    ) async throws -> Void
) async throws {
    let (session, diagnostics) = try await createSession(service: service, name: name, toolchain: toolchain, packageManagerResourcesDirectory: packageManagerResourcesDirectory)
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

package final class SwiftBuildSystemPlanningOperationDelegate: SWBPlanningOperationDelegate, SWBIndexingDelegate, Sendable {
    private let shouldEnableDebuggingEntitlement: Bool

    package init(shouldEnableDebuggingEntitlement: Bool) {
        self.shouldEnableDebuggingEntitlement = shouldEnableDebuggingEntitlement
    }

    public func provisioningTaskInputs(
        targetGUID: String,
        provisioningSourceData: SWBProvisioningTaskInputsSourceData
    ) async -> SWBProvisioningTaskInputs {
        let identity = if provisioningSourceData.signingCertificateIdentifier.isEmpty && shouldEnableDebuggingEntitlement {
            "-"
        } else {
            provisioningSourceData.signingCertificateIdentifier
        }

        if identity == "-" {
            let getTaskAllowEntitlementKey: String
            let applicationIdentifierEntitlementKey: String

            if provisioningSourceData.sdkRoot.contains("macos") || provisioningSourceData.sdkRoot
                .contains("simulator")
            {
                getTaskAllowEntitlementKey = "com.apple.security.get-task-allow"
                applicationIdentifierEntitlementKey = "com.apple.application-identifier"
            } else {
                getTaskAllowEntitlementKey = "get-task-allow"
                applicationIdentifierEntitlementKey = "application-identifier"
            }

            let signedEntitlements = provisioningSourceData
                .entitlementsDestination == "Signature" ? provisioningSourceData.productTypeEntitlements.merging(
                    [applicationIdentifierEntitlementKey: .plString(provisioningSourceData.bundleIdentifier)],
                    uniquingKeysWith: { _, new in new }
                ).merging(provisioningSourceData.projectEntitlements ?? [:], uniquingKeysWith: { _, new in new })
                : [:]

            let simulatedEntitlements = provisioningSourceData.entitlementsDestination == "__entitlements"
                ? provisioningSourceData.productTypeEntitlements.merging(
                    ["application-identifier": .plString(provisioningSourceData.bundleIdentifier)],
                    uniquingKeysWith: { _, new in new }
                ).merging(provisioningSourceData.projectEntitlements ?? [:], uniquingKeysWith: { _, new in new })
                : [:]

            var additionalEntitlements: [String: SWBPropertyListItem] = [:]

            if shouldEnableDebuggingEntitlement {
                additionalEntitlements[getTaskAllowEntitlementKey] = .plBool(true)
            }

            return SWBProvisioningTaskInputs(
                identityHash: "-",
                identityName: "-",
                profileName: nil,
                profileUUID: nil,
                profilePath: nil,
                designatedRequirements: nil,
                signedEntitlements: signedEntitlements.merging(
                    additionalEntitlements,
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

public final class SwiftBuildSystem: SPMBuildCore.BuildSystem {
    package let buildParameters: BuildParameters
    package let hostBuildParameters: BuildParameters
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
                                umbrellaProductName: package.manifest.umbrellaPackageTestsProductName,
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

    public var enableTaskBacktraces: Bool {
        self.buildParameters.outputParameters.enableTaskBacktraces
    }

    public init(
        buildParameters: BuildParameters,
        hostBuildParameters: BuildParameters,
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
        self.hostBuildParameters = hostBuildParameters
        self.packageGraphLoader = packageGraphLoader
        self.packageManagerResourcesDirectory = packageManagerResourcesDirectory
        self.additionalFileRules = additionalFileRules
        self.outputStream = outputStream
        self.logLevel = logLevel
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "Swift Build System")
        self.pluginConfiguration = pluginConfiguration
        self.delegate = delegate
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

        // TODO: Need to determine how to get the include path of package system library dependencies
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

        try await writePIF(buildParameters: self.buildParameters)

        return try await startSWBuildOperation(
            pifTargetName: subset.pifTargetName,
            buildOutputs: buildOutputs,
        )
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
                workers: self.buildParameters.workers,
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

        var replArguments: CLIArguments?
        var artifacts: [(String, PluginInvocationBuildResult.BuiltArtifact)]?
        var dependencyGraph: [String: [String]]?
        return try await withService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)) { service in
            let derivedDataPath = self.buildParameters.dataPath

            let buildMessageHandler = SwiftBuildSystemMessageHandler(
                observabilityScope: self.observabilityScope,
                outputStream: self.outputStream,
                logLevel: self.logLevel,
                enableBacktraces: self.enableTaskBacktraces,
                buildDelegate: self.delegate,
                traceEventsFilePath: self.buildParameters.outputParameters.traceEventsFilePath
            )

            do {
                try await withSession(service: service, name: self.buildParameters.pifManifest.pathString, toolchain: self.buildParameters.toolchain, packageManagerResourcesDirectory: self.packageManagerResourcesDirectory) { session, _ in
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
                    let workspaceInfo = try await session.workspaceInfo()
                    let configuredTargets: [SWBTargetGUID]
                    do {
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

                    let request = try await self.makeBuildRequest(service: service, session: session, configuredTargets: configuredTargets, derivedDataPath: derivedDataPath, symbolGraphOptions: symbolGraphOptions)

                    let operation = try await session.createBuildOperation(
                        request: request,
                        delegate: SwiftBuildSystemPlanningOperationDelegate(shouldEnableDebuggingEntitlement: self.buildParameters
                            .debuggingParameters.shouldEnableDebuggingEntitlement
                        ),
                        retainBuildDescription: true
                    )

                    var buildDescriptionID: SWBBuildDescriptionID? = nil
                    for try await event in try await operation.start() {
                        if case .reportBuildDescription(let info) = event {
                            if buildDescriptionID != nil {
                                self.observabilityScope.emit(debug: "build unexpectedly reported multiple build description IDs")
                            }
                            buildDescriptionID = SWBBuildDescriptionID(info.buildDescriptionID)
                        }
                        if let delegateCallback = try buildMessageHandler.emitEvent(event) {
                            delegateCallback(self)
                        }
                    }

                    await operation.waitForCompletion()

                    switch operation.state {
                    case .succeeded:
                        guard !self.logLevel.isQuiet else { return }
                        buildMessageHandler.progressAnimation.update(step: 100, total: 100, text: "")
                        buildMessageHandler.progressAnimation.complete(success: true)
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

                    if buildOutputs.contains(.dependencyGraph) {
                        let depGraph = try await session.computeDependencyGraph(
                            targetGUIDs: request.configuredTargets.map { SWBTargetGUID(rawValue: $0.guid) },
                            buildParameters: request.parameters,
                            includeImplicitDependencies: true
                        )
                        // SWBTargetGUID wraps the GUID that PIFBuilder generates
                        var result: [String: [String]] = [:]
                        for (target, dependencies) in depGraph {
                            let targetInfo = workspaceInfo.targetInfos.first { $0.guid == target.rawValue }
                            guard let targetName = targetInfo?.targetName else { continue }
                            let depNames = dependencies.compactMap { depGUID in
                                workspaceInfo.targetInfos.first { $0.guid == depGUID.rawValue }?.targetName
                            }
                            result[targetName] = depNames
                        }
                        dependencyGraph = result
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
                serializedDiagnosticPathsByTargetName: .success(buildMessageHandler.serializedDiagnosticPathsByTargetName),
                symbolGraph: SymbolGraphResult(
                    outputLocationForTarget: { target, buildParameters in
                        return ["\(buildParameters.triple.archName)", "\(target).symbolgraphs"]
                    }
                ),
                replArguments: replArguments,
                builtArtifacts: artifacts,
                dependencyGraph: dependencyGraph
            )
        }
    }

    private func buildTargetInfo(session: SWBBuildServiceSession) async throws -> SWBBuildTargetInfo {
        let (toolchainPath, isEmbeddedInXcode) = try toolchainDeveloperPathInfo(toolchain: buildParameters.toolchain)
        if isEmbeddedInXcode {
            return try await session.buildTargetInfo(triple: buildParameters.triple.tripleString)
        } else {
            return try await session.buildTargetInfo(triple: buildParameters.triple.tripleString)
        }
    }

    private func makeRunDestination(session: SWBBuildServiceSession) async throws -> SwiftBuild.SWBRunDestinationInfo {
        if let sdkManifestPath = self.buildParameters.toolchain.swiftSDK.swiftSDKManifest {
            return SwiftBuild.SWBRunDestinationInfo(
                buildTarget: .swiftSDK(sdkManifestPath: sdkManifestPath.pathString, triple: self.buildParameters.triple.tripleString),
                targetArchitecture: buildParameters.triple.archName,
                supportedArchitectures: [],
                disableOnlyActiveArch: (buildParameters.architectures?.count ?? 1) > 1,
            )
        } else {
            let buildTargetInfo = try await self.buildTargetInfo(session: session)

            return SwiftBuild.SWBRunDestinationInfo(
                buildTarget: .toolchainSDK(
                    platform: buildTargetInfo.platformName,
                    sdk: buildTargetInfo.sdkName,
                    sdkVariant: buildTargetInfo.sdkVariant
                ),
                targetArchitecture: buildParameters.triple.archName,
                supportedArchitectures: [],
                disableOnlyActiveArch: (buildParameters.architectures?.count ?? 1) > 1,
                hostTargetedPlatform: nil
            )
        }
    }

    internal func makeBuildParameters(
        service: SWBBuildService,
        session: SWBBuildServiceSession,
        symbolGraphOptions: BuildOutput.SymbolGraphOptions?,
        setToolchainSetting: Bool = true,
    ) async throws -> SwiftBuild.SWBBuildParameters {
        // Generate the run destination parameters.
        let runDestination = try await makeRunDestination(session: session)

        var verboseFlag: [String] = []
        if self.logLevel == .debug {
            verboseFlag = ["-v"] // Clang's verbose flag
        }

        // Generate a table of any overriding build settings.
        var settings: [String: String] = [:]

        if setToolchainSetting {
            // If the SwiftPM toolchain corresponds to a toolchain registered with the lower level build system, add it to the toolchain stack.
            // Otherwise, apply overrides for each component of the SwiftPM toolchain.
            let toolchainID = try await session.lookupToolchain(at: buildParameters.toolchain.toolchainDir.pathString)
            if toolchainID == nil {
                // FIXME: This list of overrides is incomplete.
                // An error with determining the override should not be fatal here.
                settings["CC"] = try? buildParameters.toolchain.getClangCompiler().pathStringWithPosixSlashes
                // Always specify the path of the effective Swift compiler, which was determined in the same way as for the
                // native build system.
                settings["SWIFT_EXEC"] = buildParameters.toolchain.swiftCompilerPath.pathStringWithPosixSlashes
            }

            let overrideToolchains = [buildParameters.toolchain.metalToolchainId, toolchainID?.rawValue].compactMap { $0 }
            if !overrideToolchains.isEmpty {
                settings["TOOLCHAINS"] = (overrideToolchains + ["$(inherited)"]).joined(separator: " ")
            }
        }

        for sanitizer in buildParameters.sanitizers.sanitizers {
            self.observabilityScope.emit(debug:"Enabling \(sanitizer) sanitizer")
            switch sanitizer {
                case .address:
                    settings["ENABLE_ADDRESS_SANITIZER"] = "YES"
                case .thread:
                    settings["ENABLE_THREAD_SANITIZER"] = "YES"
                case .undefined:
                    settings["ENABLE_UNDEFINED_BEHAVIOR_SANITIZER"] = "YES"
                case .fuzzer, .scudo:
                    throw StringError("\(sanitizer) is not currently supported with this build system.")
            }
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

        if !buildParameters.customToolsetPaths.isEmpty {
            settings["SWIFT_SDK_TOOLSETS"] =
                (["$(inherited)"] + buildParameters.customToolsetPaths.map { $0.pathStringWithPosixSlashes })
                .joined(separator: " ")
        }

        let buildTargetInfo = try await self.buildTargetInfo(session: session)
        if let deploymentTargetSettingName = buildTargetInfo.deploymentTargetSettingName, let value = buildTargetInfo.deploymentTarget {
            // Only override the deployment target if a version is explicitly specified;
            // for Apple platforms this normally comes from the package manifest and may
            // not be set to the same value for all packages in the package graph.
            settings[deploymentTargetSettingName] = value
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

        var swiftCompilerFlags = buildParameters.toolchain.extraFlags.swiftCompilerFlags + buildParameters.flags.swiftCompilerFlags
        swiftCompilerFlags += buildParameters.toolchain.extraFlags.cCompilerFlags.asSwiftcCCompilerFlags()
        // User arguments (from -Xcc) should follow generated arguments to allow user overrides
        swiftCompilerFlags += buildParameters.flags.cCompilerFlags.asSwiftcCCompilerFlags()

        // TODO: Pass -Xcxx flags to swiftc (#6491)
        // Uncomment when downstream support arrives.
        // swiftCompilerFlags += buildParameters.toolchain.extraFlags.cxxCompilerFlags.rawFlags.asSwiftcCXXCompilerFlags()
        // // User arguments (from -Xcxx) should follow generated arguments to allow user overrides
        // swiftCompilerFlags += buildParameters.flags.cxxCompilerFlags.rawFlags.asSwiftcCXXCompilerFlags()
        let compilerAndLinkerFlags = [
            "OTHER_CFLAGS": buildParameters.toolchain.extraFlags.cCompilerFlags + buildParameters.flags.cCompilerFlags,
            "OTHER_CPLUSPLUSFLAGS": buildParameters.toolchain.extraFlags.cxxCompilerFlags + buildParameters.flags.cxxCompilerFlags,
            "OTHER_SWIFT_FLAGS": swiftCompilerFlags,
            "OTHER_LDFLAGS": (buildParameters.toolchain.extraFlags.linkerFlags + buildParameters.flags.linkerFlags)
        ]
        for (settingName, buildFlags) in compilerAndLinkerFlags {
            var rawFlags = buildFlags.rawFlagsForSwiftBuild
            if settingName == "OTHER_LDFLAGS" {
                rawFlags = rawFlags.asSwiftcLinkerFlags()
            }
            settings[settingName] = (verboseFlag + ["$(inherited)"] +
                rawFlags.map { $0.shellEscaped() }).joined(separator: " ")
        }

        // Historically, SwiftPM passed -Xswiftc flags to swiftc when used as a linker driver.
        // To maintain compatibility, forward swift compiler flags to OTHER_LDFLAGS when using
        // swiftc to link.
        if !swiftCompilerFlags.rawFlagsForSwiftBuild.isEmpty {
            settings["OTHER_LDFLAGS_SWIFTC_LINKER_DRIVER_swiftc"] =
            (["$(inherited)"] + swiftCompilerFlags.rawFlagsForSwiftBuild.map { $0.shellEscaped() }).joined(separator: " ")
            settings["OTHER_LDFLAGS"] =
                (settings["OTHER_LDFLAGS"] ?? "$(inherited)") + " $(OTHER_LDFLAGS_SWIFTC_LINKER_DRIVER_$(LINKER_DRIVER))"
        }

        if buildParameters.driverParameters.emitSILFiles {
            settings["SWIFT_EMIT_SIL_FILES"] = "YES"
            if let outputDir = buildParameters.driverParameters.silOutputDirectory {
                settings["SWIFT_SIL_OUTPUT_DIR"] = outputDir.pathString
            }
        }

        if buildParameters.driverParameters.emitIRFiles {
            settings["SWIFT_EMIT_IR_FILES"] = "YES"
            if let outputDir = buildParameters.driverParameters.irOutputDirectory {
                settings["SWIFT_IR_OUTPUT_DIR"] = outputDir.pathStringWithPosixSlashes
            }
        }

        if buildParameters.driverParameters.emitOptimizationRecord {
            settings["SWIFT_EMIT_OPT_RECORDS"] = "YES"
            if let outputDir = buildParameters.driverParameters.optimizationRecordDirectory {
                settings["SWIFT_OPT_RECORD_OUTPUT_DIR"] = outputDir.pathStringWithPosixSlashes
            }
        }

        // Optionally also set the list of architectures to build for.
        if let architectures = buildParameters.architectures, !architectures.isEmpty {
            settings["ARCHS"] = architectures.joined(separator: " ")
        } else {
            // If the user did not explicitly specify a list of architectures, build only the active arch.
            // We may want to consider building universal binaries by default in Apple-platform release builds
            // in the future, but for now we maintain compatibility with the old build system.
            settings["ONLY_ACTIVE_ARCH"] = "YES"
        }

        // When building with the CLI for macOS, test bundles should generate entrypoints for compatibility with swiftpm-testing-helper.
        if buildParameters.triple.isMacOSX {
            settings["GENERATE_TEST_ENTRYPOINTS_FOR_BUNDLES"] = "YES"
        }

        // Set the value of the index store
        struct IndexStoreSettings {
            let enableVariableName: String
            let pathVariable: String
        }

        let indexStoreSettingNames: [IndexStoreSettings] = [
            IndexStoreSettings(
                enableVariableName: "CLANG_INDEX_STORE_ENABLE",
                pathVariable: "CLANG_INDEX_STORE_PATH",
            ),
            IndexStoreSettings(
                enableVariableName: "SWIFT_INDEX_STORE_ENABLE",
                pathVariable: "SWIFT_INDEX_STORE_PATH",
            ),
        ]

        switch self.buildParameters.indexStoreMode {
        case .on:
            for setting in indexStoreSettingNames {
                settings[setting.enableVariableName] = "YES"
                settings[setting.pathVariable] = self.buildParameters.indexStore.pathStringWithPosixSlashes
            }
        case .off:
            for setting in indexStoreSettingNames {
                settings[setting.enableVariableName] = "NO"
            }
        case .auto:
            // The settings are handles in the PIF builder
            break
        }

        // Added for compatibility with --build-system native, but we should try to phase these out in the future
        settings["ADD_TOOLCHAIN_CONCURRENCY_BACK_DEPLOY_RPATH"] = "YES"
        settings["ADD_TOOLCHAIN_SPAN_BACK_DEPLOY_RPATH"] = "YES"

        func reportConflict(_ a: String, _ b: String) throws -> String {
            throw StringError("Build parameters constructed conflicting settings overrides '\(a)' and '\(b)'")
        }
        try settings.merge(Self.constructDebuggingSettingsOverrides(from: buildParameters.debuggingParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructDriverSettingsOverrides(from: buildParameters.driverParameters), uniquingKeysWith: reportConflict)
        try settings.merge(self.constructLinkerSettingsOverrides(from: buildParameters.linkingParameters, triple: buildParameters.triple), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructTestingSettingsOverrides(from: buildParameters.testingParameters), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructAPIDigesterSettingsOverrides(from: buildParameters.apiDigesterMode), uniquingKeysWith: reportConflict)
        try settings.merge(Self.constructOutputSettingsOverrides(from: buildParameters.outputParameters), uniquingKeysWith: reportConflict)

        if buildParameters.driverParameters.codesizeProfileEnabled {
            // dSYM generation is required to attribute code size to source locations
            if let debugFormat = settings["DEBUG_INFORMATION_FORMAT"] {
                self.observabilityScope.emit(warning: "--experimental-enable-codesize-profile requires 'dwarf-with-dsym' debug format, overriding the user specified value of '\(debugFormat)''")
            }
            settings["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        }

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

    public func makeBuildRequest(
        service: SWBBuildService,
        session: SWBBuildServiceSession,
        configuredTargets: [SWBTargetGUID],
        derivedDataPath: Basics.AbsolutePath,
        symbolGraphOptions: BuildOutput.SymbolGraphOptions?,
        setToolchainSetting: Bool = true,
        ) async throws -> SWBBuildRequest {
        var request = SWBBuildRequest()
        request.parameters = try await makeBuildParameters(
            service: service,
            session: session,
            symbolGraphOptions: symbolGraphOptions,
            setToolchainSetting: setToolchainSetting,
        )
        request.configuredTargets = configuredTargets.map { SWBConfiguredTarget(guid: $0.rawValue, parameters: request.parameters) }
        request.useParallelTargets = true
        request.useImplicitDependencies = false
        request.useDryRun = false
        request.hideShellScriptEnvironment = true
        request.showNonLoggedProgress = true
        request.recordBuildBacktraces = buildParameters.outputParameters.enableTaskBacktraces
        request.schedulerLaneWidthOverride = buildParameters.workers

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
        if parameters.shouldEnableDebuggingEntitlement {
            settings["DEPLOYMENT_POSTPROCESSING"] = "NO"
        }
        // Set DEBUG_INFORMATION_FORMAT based on debugInfoFormat
        switch parameters.debugInfoFormat {
        case .dwarf:
            settings["DEBUG_INFORMATION_FORMAT"] = "dwarf"
        case .codeview:
            settings["DEBUG_INFORMATION_FORMAT"] = "codeview"
        case .none?:
            settings["GCC_GENERATE_DEBUGGING_SYMBOLS"] = "NO"
            break
        case nil:
            break
        }
        if let omitFramePointers = parameters.omitFramePointers {
            if omitFramePointers {
                settings["CLANG_OMIT_FRAME_POINTERS"] = "YES"
                settings["SWIFT_OMIT_FRAME_POINTERS"] = "YES"
            } else {
                settings["CLANG_OMIT_FRAME_POINTERS"] = "NO"
                settings["SWIFT_OMIT_FRAME_POINTERS"] = "NO"
            }
        }
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

    private func constructLinkerSettingsOverrides(
        from parameters: BuildParameters.Linking,
        triple: Triple,
    ) -> [String: String] {
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

        if triple.isDarwin() && parameters.shouldLinkStaticSwiftStdlib {
            self.observabilityScope.emit(Basics.Diagnostic.swiftBackDeployWarning)
        } else {
            if parameters.shouldLinkStaticSwiftStdlib {
                settings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = "YES"
            } else {
                settings["SWIFT_FORCE_STATIC_LINK_STDLIB"] = "NO"
            }
        }

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
            settings["SWIFT_API_DIGESTER_MODE"] = SwiftAPIDigesterMode.api.rawValue
            for module in modulesRequestingBaselines {
                settings["RUN_SWIFT_ABI_GENERATION_TOOL_MODULE_\(module)"] = "YES"
            }
            settings["RUN_SWIFT_ABI_GENERATION_TOOL"] = "$(RUN_SWIFT_ABI_GENERATION_TOOL_MODULE_$(PRODUCT_MODULE_NAME))"
            settings["SWIFT_ABI_GENERATION_TOOL_OUTPUT_DIR"] = baselinesDirectory.appending(components: ["$(PRODUCT_MODULE_NAME)", "ABI"]).pathStringWithPosixSlashes
        case .compareToBaselines(let baselinesDirectory, let modulesToCompare, let breakageAllowListPath):
            settings["SWIFT_API_DIGESTER_MODE"] = SwiftAPIDigesterMode.api.rawValue
            settings["SWIFT_ABI_CHECKER_DOWNGRADE_ERRORS"] = "YES"
            for module in modulesToCompare {
                settings["RUN_SWIFT_ABI_CHECKER_TOOL_MODULE_\(module)"] = "YES"
            }
            settings["RUN_SWIFT_ABI_CHECKER_TOOL"] = "$(RUN_SWIFT_ABI_CHECKER_TOOL_MODULE_$(PRODUCT_MODULE_NAME))"
            settings["SWIFT_ABI_CHECKER_BASELINE_DIR"] = baselinesDirectory.appending(component: "$(PRODUCT_MODULE_NAME)").pathStringWithPosixSlashes
            if let breakageAllowListPath {
                settings["SWIFT_ABI_CHECKER_EXCEPTIONS_FILE"] = breakageAllowListPath.pathStringWithPosixSlashes
            }
        case nil:
            break
        }
        return settings
    }

    private static func constructOutputSettingsOverrides(from parameters: BuildParameters.Output) -> [String: String] {
        var settings: [String: String] = [:]
        settings["COLOR_DIAGNOSTICS"] = parameters.isColorized ? "YES" : "NO"
        return settings
    }

    private func getPIFBuilder() async throws -> PIFBuilder {
        try await pifBuilder.memoize {
            let graph = try await getPackageGraph()
            // materializeStaticArchiveProductsForRootPackages currently has some minor compatibility
            // issues when building interdependent root packages on Windows, primarily where projects
            // like swift-corelibs-foundation relied on specific linkage patterns when using
            // @_dynamicReplacement(for:). For now, disable this option if there is more than one
            // root package, but we should reconsider this decision in the future.
            let materializeStaticArchiveProductsForRootPackages = graph.rootPackages.count == 1
            let pifBuilder = try PIFBuilder(
                graph: graph,
                parameters: .init(
                    buildParameters,
                    supportedSwiftVersions: supportedSwiftVersions(),
                    pluginScriptRunner: self.pluginConfiguration.scriptRunner,
                    disableSandbox: self.pluginConfiguration.disableSandbox,
                    pluginWorkingDirectory: self.pluginConfiguration.workDirectory,
                    additionalFileRules: additionalFileRules,
                    addLocalRpaths: !self.buildParameters.linkingParameters.shouldDisableLocalRpath,
                    materializeStaticArchiveProductsForRootPackages: materializeStaticArchiveProductsForRootPackages,
                    createDynamicVariantsForLibraryProducts: false,
                ),
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope,
            )
            return pifBuilder
        }
    }

    public func generatePIF(preserveStructure: Bool) async throws -> String {
        pifBuilder = .init()
        packageGraph = .init()
        let pifBuilder = try await getPIFBuilder()
        let pif = try await pifBuilder.generatePIF(
            preservePIFModelStructure: preserveStructure,
            printPIFManifestGraphviz: buildParameters.printPIFManifestGraphviz,
            buildParameters: buildParameters,
            hostBuildParameters: hostBuildParameters
        )
        return pif
    }

    public func writePIF(buildParameters: BuildParameters) async throws {
        let pif = try await generatePIF(preserveStructure: false)
        try self.fileSystem.writeIfChanged(path: buildParameters.pifManifest, string: pif)
    }

    package struct LongLivedBuildServiceSession {
        package var service: SWBBuildService
        package var session: SWBBuildServiceSession
        package var diagnostics: [SwiftBuildMessage.DiagnosticInfo]
        package var teardownHandler: () async throws -> Void
    }

    package func createLongLivedSession(name: String) async throws -> LongLivedBuildServiceSession {
        let service = try await SWBBuildService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint))
        do {
            let (session, diagnostics) = try await createSession(service: service, name: name, toolchain: buildParameters.toolchain, packageManagerResourcesDirectory: packageManagerResourcesDirectory)
            let teardownHandler = {
                try await session.close()
                await service.close()
            }
            return LongLivedBuildServiceSession(service: service, session: session, diagnostics: diagnostics, teardownHandler: teardownHandler)
        } catch {
            await service.close()
            throw error
        }
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

extension Basics.AbsolutePath {
    /// Returns a string representation of the path which uses POSIX slashes even on Windows.
    ///
    /// This is necessary for some cases where tools may treat the `\` character as part of an escape sequence rather than a path separator even on Windows. Use sparingly.
    public var pathStringWithPosixSlashes: String {
        #if os(Windows)
        pathString.replacingOccurrences(of: "\\", with: "/")
        #else
        pathString
        #endif
    }
}

fileprivate extension [BuildFlag] {
    var rawFlagsForSwiftBuild: [String] {
        filter {
            switch $0.source {
            case .commandLineOptions:
                // Flags specified by the user. These are generally the only ones that should be passed on.
                return true
            case .plugin:
                // FIXME: Not yet handled
                return true
            case .debugging:
                return false
            case .toolset:
                // Swift Build loads toolset flags internally as part of loading Swift SDKs, or by passing the custom toolsets
                // via the SWIFT_SDK_TOOLSETS build setting, and may introspect them to override build settings.
                // Don't duplicate them here.
                return false
            case .defaultSwiftTestingSearchPath:
                // Swift Build computes these internally. It's important not to add them a second time here
                // as it can break the intended search path ordering, for example, if the user is building
                // Swift Testing as a package dependency.
                return false
            case .defaultWindowsSettings:
                // Swift Build computes these internally.
                return false
            case .swiftSDK:
                // Swift Build loads Swift SDK flags internally, and may introspect them to override build
                // settings. Don't duplicate them here.
                return false
            case nil:
                // Remaining flags are legacy build system specific (one occurrence only), or in tests.
                return false
            }
        }.map { $0.value }
    }

    /// Converts a set of C compiler flags into an equivalent set to be
    /// indirected through the Swift compiler instead.
    func asSwiftcCCompilerFlags() -> [BuildFlag] {
        self.flatMap { [BuildFlag(value: "-Xcc", source: $0.source), $0] }
    }
}
