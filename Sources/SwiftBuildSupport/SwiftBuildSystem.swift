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

@_spi(SwiftPMInternal)
import SPMBuildCore

import class Basics.AsyncProcess
import func TSCBasic.memoize
import protocol TSCBasic.OutputByteStream
import func TSCBasic.withTemporaryFile

import enum TSCUtility.Diagnostics

#if canImport(SwiftBuild)
import Foundation
import SWBBuildService
import SwiftBuild
#endif

#if canImport(SwiftBuild)

struct SessionFailedError: Error {
    var error: Error
    var diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
}

func withService(
    connectionMode: SWBBuildServiceConnectionMode = .default,
    variant: SWBBuildServiceVariant = .default,
    serviceBundleURL: URL? = nil,
    body: @escaping (_ service: SWBBuildService) async throws -> Void
) async throws {
    let service = try await SWBBuildService(connectionMode: connectionMode, variant: variant, serviceBundleURL: serviceBundleURL)
    do {
        try await body(service)
    } catch {
        await service.close()
        throw error
    }
    await service.close()
}

func withSession(
    service: SWBBuildService,
    name: String,
    packageManagerResourcesDirectory: Basics.AbsolutePath?,
    body: @escaping (
        _ session: SWBBuildServiceSession,
        _ diagnostics: [SwiftBuild.SwiftBuildMessage.DiagnosticInfo]
    ) async throws -> Void
) async throws {
    switch await service.createSession(name: name, resourceSearchPaths: packageManagerResourcesDirectory.map { [$0.pathString] } ?? [], cachePath: nil, inferiorProductsPath: nil, environment: nil) {
    case (.success(let session), let diagnostics):
        do {
            try await body(session, diagnostics)
        } catch {
            do {
                try await session.close()
            } catch _ {
                // Assumption is that the first error is the most important one
                throw SessionFailedError(error: error, diagnostics: diagnostics)
            }

            throw SessionFailedError(error: error, diagnostics: diagnostics)
        }

        do {
            try await session.close()
        } catch {
            throw SessionFailedError(error: error, diagnostics: diagnostics)
        }
    case (.failure(let error), let diagnostics):
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
#endif

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

    public init(
        buildParameters: BuildParameters,
        packageGraphLoader: @escaping () async throws -> ModulesGraph,
        packageManagerResourcesDirectory: Basics.AbsolutePath?,
        outputStream: OutputByteStream,
        logLevel: Basics.Diagnostic.Severity,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        self.buildParameters = buildParameters
        self.packageGraphLoader = packageGraphLoader
        self.packageManagerResourcesDirectory = packageManagerResourcesDirectory
        self.outputStream = outputStream
        self.logLevel = logLevel
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope.makeChildScope(description: "Swift Build System")
    }

    private func supportedSwiftVersions() throws -> [SwiftLanguageVersion] {
        // Swift Build should support any of the supported language versions of SwiftPM and the rest of the toolchain
        SwiftLanguageVersion.supportedSwiftLanguageVersions
    }

    public func build(subset: BuildSubset) async throws {
        #if canImport(SwiftBuild)
        guard !buildParameters.shouldSkipBuilding else {
            return
        }

        let pifBuilder = try await getPIFBuilder()
        let pif = try pifBuilder.generatePIF()

        try self.fileSystem.writeIfChanged(path: buildParameters.pifManifest, string: pif)

        try await startSWBuildOperation(pifTargetName: subset.pifTargetName)

        #else
        fatalError("Swift Build support is not linked in.")
        #endif
    }

    #if canImport(SwiftBuild)
    private func startSWBuildOperation(pifTargetName: String) async throws {
        let buildStartTime = ContinuousClock.Instant.now

        try await withService(connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)) { service in
            let parameters = try self.makeBuildParameters()
            let derivedDataPath = self.buildParameters.dataPath.pathString

            let progressAnimation = ProgressAnimation.percent(
                stream: self.outputStream,
                verbose: self.logLevel.isVerbose,
                header: "",
                isColorized: self.buildParameters.outputParameters.isColorized
            )

            do {
                try await withSession(service: service, name: self.buildParameters.pifManifest.pathString, packageManagerResourcesDirectory: self.packageManagerResourcesDirectory) { session, _ in
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
                    let configuredTargets: [SWBConfiguredTarget]
                    do {
                        let workspaceInfo = try await session.workspaceInfo()

                        configuredTargets = try [pifTargetName].map { targetName in
                            let infos = workspaceInfo.targetInfos.filter { $0.targetName == targetName }
                            switch infos.count {
                            case 0:
                                self.observabilityScope.emit(error: "Could not find target named '\(targetName)'")
                                throw Diagnostics.fatalError
                            case 1:
                                return SWBConfiguredTarget(guid: infos[0].guid, parameters: parameters)
                            default:
                                self.observabilityScope.emit(error: "Found multiple targets named '\(targetName)'")
                                throw Diagnostics.fatalError
                            }
                        }
                    } catch {
                        self.observabilityScope.emit(error: error.localizedDescription)
                        throw error
                    }

                    var request = SWBBuildRequest()
                    request.parameters = parameters
                    request.configuredTargets = configuredTargets
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
                    let ddPathPrefix = derivedDataPath.replacingOccurrences(of: "\\", with: "/")
                    #else
                    let ddPathPrefix = derivedDataPath
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

                    func emitEvent(_ message: SwiftBuild.SwiftBuildMessage) throws {
                        switch message {
                        case .buildCompleted:
                            progressAnimation.complete(success: true)
                        case .didUpdateProgress(let progressInfo):
                            var step = Int(progressInfo.percentComplete)
                            if step < 0 { step = 0 }
                            let message = if let targetName = progressInfo.targetName {
                                "\(targetName) \(progressInfo.message)"
                            } else {
                                "\(progressInfo.message)"
                            }
                            progressAnimation.update(step: step, total: 100, text: message)
                        case .diagnostic(let info):
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
                        case .taskOutput(let info):
                            self.observabilityScope.emit(info: "\(info.data)")
                        case .taskStarted(let info):
                            if let commandLineDisplay = info.commandLineDisplayString {
                                self.observabilityScope.emit(info: "\(info.executionDescription)\n\(commandLineDisplay)")
                            } else {
                                self.observabilityScope.emit(info: "\(info.executionDescription)")
                            }
                        default:
                            break
                        }
                    }

                    let operation = try await session.createBuildOperation(
                        request: request,
                        delegate: PlanningOperationDelegate()
                    )

                    for try await event in try await operation.start() {
                        try emitEvent(event)
                    }

                    await operation.waitForCompletion()

                    switch operation.state {
                    case .succeeded:
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
        }
    }

    func makeBuildParameters() throws -> SwiftBuild.SWBBuildParameters {
        // Generate the run destination parameters.
        let runDestination = SwiftBuild.SWBRunDestinationInfo(
            platform: self.buildParameters.triple.osNameUnversioned,
            sdk: self.buildParameters.triple.osNameUnversioned,
            sdkVariant: nil,
            targetArchitecture: buildParameters.triple.archName,
            supportedArchitectures: [],
            disableOnlyActiveArch: false
        )

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

        // support for --enable-parseable-module-interfaces
        if buildParameters.driverParameters.enableParseableModuleInterfaces {
            settings["SWIFT_EMIT_MODULE_INTERFACE"] = "YES"
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

    private func getPIFBuilder() async throws -> PIFBuilder {
        try await pifBuilder.memoize {
            let graph = try await getPackageGraph()
            let pifBuilder = try PIFBuilder(
                graph: graph,
                parameters: .init(buildParameters, supportedSwiftVersions: supportedSwiftVersions()),
                fileSystem: self.fileSystem,
                observabilityScope: self.observabilityScope
            )
            return pifBuilder
        }
    }
    #endif

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

extension PIFBuilderParameters {
    public init(_ buildParameters: BuildParameters, supportedSwiftVersions: [SwiftLanguageVersion]) {
        self.init(
            triple: buildParameters.triple,
            isPackageAccessModifierSupported: buildParameters.driverParameters.isPackageAccessModifierSupported,
            enableTestability: buildParameters.enableTestability,
            shouldCreateDylibForDynamicProducts: buildParameters.shouldCreateDylibForDynamicProducts,
            toolchainLibDir: (try? buildParameters.toolchain.toolchainLibDir) ?? .root,
            pkgConfigDirectories: buildParameters.pkgConfigDirectories,
            sdkRootPath: buildParameters.toolchain.sdkRootPath,
            supportedSwiftVersions: supportedSwiftVersions
        )
    }
}

extension Basics.Diagnostic.Severity {
    var isVerbose: Bool {
        self <= .info
    }
}

#if canImport(SwiftBuild)

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

#endif
