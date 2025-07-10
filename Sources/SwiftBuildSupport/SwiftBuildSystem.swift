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
    let sessionResult = if toolchainPath.components.contains(where: { $0.hasSuffix(".xctoolchain") }) {
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

public struct PluginConfiguration {
    /// Entity responsible for compiling and running plugin scripts.
    let scriptRunner: PluginScriptRunner

    /// Directory where plugin intermediate files are stored.
    let workDirectory: Basics.AbsolutePath

    /// Whether to sandbox commands from build tool plugins.
    let disableSandbox: Bool

    public init(
        scriptRunner: PluginScriptRunner,
        workDirectory: Basics.AbsolutePath,
        disableSandbox: Bool
    ) {
        self.scriptRunner = scriptRunner
        self.workDirectory = workDirectory
        self.disableSandbox = disableSandbox
    }
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
        self.delegate = delegate
    }

    private func supportedSwiftVersions() throws -> [SwiftLanguageVersion] {
        // Swift Build should support any of the supported language versions of SwiftPM and the rest of the toolchain
        SwiftLanguageVersion.supportedSwiftLanguageVersions
    }

    public func build(subset: BuildSubset) async throws -> BuildResult {
        guard !buildParameters.shouldSkipBuilding else {
            return BuildResult(serializedDiagnosticPathsByTargetName: .failure(StringError("Building was skipped")))
        }

        try await writePIF(buildParameters: buildParameters)

        return try await startSWBuildOperation(pifTargetName: subset.pifTargetName)
    }

    private func startSWBuildOperation(pifTargetName: String) async throws -> BuildResult {
        let buildStartTime = ContinuousClock.Instant.now

        return try await withService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)) { service in
            let derivedDataPath = self.buildParameters.dataPath

            let progressAnimation = ProgressAnimation.percent(
                stream: self.outputStream,
                verbose: self.logLevel.isVerbose,
                header: "",
                isColorized: self.buildParameters.outputParameters.isColorized
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

                    let request = try self.makeBuildRequest(configuredTargets: configuredTargets, derivedDataPath: derivedDataPath)

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
                                self.observabilityScope.emit(severity: severity, message: message)

                                for childDiagnostic in info.childDiagnostics {
                                    emitInfoAsDiagnostic(info: childDiagnostic)
                                }
                            }

                            emitInfoAsDiagnostic(info: info)
                        case .output(let info):
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
                                self.observabilityScope.emit(severity: .error, message: "\(startedInfo.ruleInfo) failed with a nonzero exit code")
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
                        delegate: PlanningOperationDelegate()
                    )

                    var buildState = BuildState()
                    for try await event in try await operation.start() {
                        try emitEvent(event, buildState: &buildState)
                    }

                    await operation.waitForCompletion()

                    switch operation.state {
                    case .succeeded:
                        guard !self.logLevel.isQuiet else { return }
                        progressAnimation.update(step: 100, total: 100, text: "")
                        progressAnimation.complete(success: true)
                        let duration = ContinuousClock.Instant.now - buildStartTime
                        self.outputStream.send("Build complete! (\(duration))\n")
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
                }
            } catch let sessError as SessionFailedError {
                for diagnostic in sessError.diagnostics {
                    self.observabilityScope.emit(error: diagnostic.message)
                }
                throw sessError.error
            } catch {
                throw error
            }
            return BuildResult(serializedDiagnosticPathsByTargetName: .success(serializedDiagnosticPathsByTargetName))
        }
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
            disableOnlyActiveArch: false
        )
    }

    private func makeBuildParameters() throws -> SwiftBuild.SWBBuildParameters {
        // Generate the run destination parameters.
        let runDestination = makeRunDestination()

        var verboseFlag: [String] = []
        if self.logLevel == .debug {
            verboseFlag = ["-v"] // Clang's verbose flag
        }

        // Generate a table of any overriding build settings.
        var settings: [String: String] = [:]
        // An error with determining the override should not be fatal here.
        settings["CC"] = try? buildParameters.toolchain.getClangCompiler().pathString
        // Always specify the path of the effective Swift compiler, which was determined in the same way as for the
        // native build system.
        settings["SWIFT_EXEC"] = buildParameters.toolchain.swiftCompilerPath.pathString
        // FIXME: workaround for old Xcode installations such as what is in CI
        settings["LM_SKIP_METADATA_EXTRACTION"] = "YES"

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

        settings["LIBRARY_SEARCH_PATHS"] = try "$(inherited) \(buildParameters.toolchain.toolchainLibDir.pathString)"
        settings["OTHER_CFLAGS"] = (
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.cCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.cCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")
        settings["OTHER_CPLUSPLUSFLAGS"] = (
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.cxxCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.cxxCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")
        settings["OTHER_SWIFT_FLAGS"] = (
            ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.swiftCompilerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.swiftCompilerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")

        settings["OTHER_LDFLAGS"] = (
            verboseFlag + // clang will be invoked to link so the verbose flag is valid for it
                ["$(inherited)"]
                + buildParameters.toolchain.extraFlags.linkerFlags.map { $0.shellEscaped() }
                + buildParameters.flags.linkerFlags.map { $0.shellEscaped() }
        ).joined(separator: " ")

        // Optionally also set the list of architectures to build for.
        if let architectures = buildParameters.architectures, !architectures.isEmpty {
            settings["ARCHS"] = architectures.joined(separator: " ")
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

    public func makeBuildRequest(configuredTargets: [SWBTargetGUID], derivedDataPath: Basics.AbsolutePath) throws -> SWBBuildRequest {
        var request = SWBBuildRequest()
        request.parameters = try makeBuildParameters()
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
        // TODO: enableCodeCoverage
        // explicitlyEnabledTestability

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
                observabilityScope: self.observabilityScope
            )
            return pifBuilder
        }
    }

    public func writePIF(buildParameters: BuildParameters) async throws {
        let pifBuilder = try await getPIFBuilder()
        let pif = try await pifBuilder.generatePIF(
            printPIFManifestGraphviz: buildParameters.printPIFManifestGraphviz,
            buildParameters: buildParameters,
        )

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
