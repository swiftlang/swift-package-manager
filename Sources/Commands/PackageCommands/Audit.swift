//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Foundation
import PackageAudit
import PackageFingerprint
import PackageGraph
import PackageModel
import PackageRegistry
import PackageSigning
import Workspace

import struct TSCBasic.SHA256
import var TSCBasic.stdoutStream

/// The output format of `swift package audit`.
enum AuditOutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text, json
}

// `unknown` is a severity that advisories can have, but not a meaningful threshold.
extension AdvisorySeverity: ExpressibleByArgument {
    public init?(argument: String) {
        guard let severity = AdvisorySeverity(rawValue: argument.lowercased()), severity != .unknown else {
            return nil
        }
        self = severity
    }

    public static var allValueStrings: [String] {
        Self.allCases.filter { $0 != .unknown }.map(\.rawValue)
    }
}

/// Options shared by `swift package audit` and its subcommands.
struct AuditOptions: ParsableArguments {
    @Option(help: ArgumentHelp(
        "Lowest severity that causes a failing exit status.",
        valueName: "low|moderate|high|critical"
    ))
    var severityThreshold: AdvisorySeverity = .low

    @Option(help: ArgumentHelp("Output format.", valueName: "text|json"))
    var format: AuditOutputFormat = .text

    @Option(help: ArgumentHelp("Ignore an advisory by ID or alias. Can be repeated.", valueName: "id"))
    var ignore: [String] = []

    @Flag(help: "Fail if any package could not be checked.")
    var failOnUnchecked: Bool = false

    @Option(help: ArgumentHelp(
        "OSV-compatible database to query (an https:// or file:// URL).",
        valueName: "url"
    ))
    var advisoryDatabase: String?

    @Flag(help: "Do not query an OSV-compatible database.")
    var noAdvisoryDatabase: Bool = false

    @Flag(help: "Do not query package registries for advisories.")
    var noRegistryAdvisories: Bool = false

    func validate() throws {
        if self.noAdvisoryDatabase && self.noRegistryAdvisories {
            throw ValidationError(
                "'--no-advisory-database' and '--no-registry-advisories' cannot be used together; at least one advisory source is required"
            )
        }
    }
}

extension SwiftPackageCommand {
    struct Audit: AsyncSwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "audit",
            abstract: "Check dependencies for known security vulnerabilities.",
            subcommands: [Fix.self],
            helpNames: [.short, .long, .customLong("help", withSingleDash: true)]
        )

        /// The advisory database used when none is passed or configured.
        static let defaultAdvisoryDatabase = "https://api.osv.dev"

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var options: AuditOptions

        func run(_ swiftCommandState: SwiftCommandState) async throws {
            let (report, _, _, _) = try await Self.runAudit(options: self.options, swiftCommandState: swiftCommandState)
            try Self.printReport(report, options: self.options, swiftCommandState: swiftCommandState)
            try Self.exitForReport(report, options: self.options, swiftCommandState: swiftCommandState)
        }

        /// Writes `report` to standard output in the requested format.
        static func printReport(
            _ report: AuditReport,
            options: AuditOptions,
            swiftCommandState: SwiftCommandState
        ) throws {
            var output: String
            switch options.format {
            case .text:
                output = AuditReportRenderer.text(report, verbose: swiftCommandState.logLevel <= .info)
            case .json:
                output = try AuditReportRenderer.json(report)
            }
            if !output.hasSuffix("\n") {
                output += "\n"
            }
            stdoutStream.send(output)
            stdoutStream.flush()
        }

        /// Throws the exit status for `report`, if it is not 0.
        static func exitForReport(
            _ report: AuditReport,
            options: AuditOptions,
            swiftCommandState: SwiftCommandState
        ) throws {
            // Findings are reported through the exit status rather than as errors, which would force status 1.
            let status = report.exitStatus(
                threshold: options.severityThreshold,
                failOnUnchecked: options.failOnUnchecked
            )
            if swiftCommandState.observabilityScope.errorsReported {
                throw ExitCode.failure
            }
            if status != 0 {
                throw ExitCode(status)
            }
        }

        /// Loads the package graph (with all traits enabled where `Package.resolved` allows), audits its resolved
        /// packages and classifies how each finding can be fixed.
        ///
        /// Returns the report with the graph, workspace and root input it was produced from.
        /// Failures of any advisory source or of the classification are thrown.
        static func runAudit(
            options: AuditOptions,
            swiftCommandState: SwiftCommandState
        ) async throws -> (AuditReport, ModulesGraph, Workspace, PackageGraphRootInput) {
            let (graph, workspace, root) = try await Self.loadGraph(swiftCommandState: swiftCommandState)

            let packages = AuditInputBuilder.makePackages(
                graph: graph,
                resolvedPackages: try workspace.resolvedPackagesStore.load()
            )

            let database: (any AdvisoryDatabase)?
            if options.noAdvisoryDatabase {
                database = nil
            } else {
                database = try makeAdvisoryDatabase(
                    url: try Self.advisoryDatabaseURL(options: options, workspace: workspace, swiftCommandState: swiftCommandState),
                    httpClient: HTTPClient(),
                    fileSystem: swiftCommandState.fileSystem
                )
            }

            var registry: (any RegistryAdvisoryProvider)?
            let hasRegistryPackages = packages.contains { package in
                if case .registry = package.kind { return true }
                return false
            }
            if !options.noRegistryAdvisories && hasRegistryPackages {
                registry = RegistryAdvisorySource(
                    client: try Self.makeRegistryClient(workspace: workspace, swiftCommandState: swiftCommandState),
                    observabilityScope: swiftCommandState.observabilityScope
                )
            }

            let auditor = PackageAuditor(database: database, registry: registry, ignoredIDs: Set(options.ignore))
            let report = try await auditor.audit(packages)

            let classified = try await FixClassifier(
                workspace: workspace,
                root: root,
                graph: graph,
                observabilityScope: swiftCommandState.observabilityScope
            ).classify(report)

            return (classified, graph, workspace, root)
        }

        /// Loads the graph to audit without changing `Package.resolved`.
        ///
        /// Dependencies are first resolved as for any other command, with the package's own trait configuration.
        /// The graph with all traits enabled is then loaded from `Package.resolved` alone, so that dependencies only
        /// used with other traits are audited when they are pinned, but never pinned by audit. If that is not
        /// possible (for example because such a dependency is not pinned), the first graph is audited instead.
        private static func loadGraph(
            swiftCommandState: SwiftCommandState
        ) async throws -> (ModulesGraph, Workspace, PackageGraphRootInput) {
            let workspace = try swiftCommandState.getActiveWorkspace()
            let root = try swiftCommandState.getWorkspaceRoot()

            let graphScope = swiftCommandState.observabilityScope.makeChildScope(description: "Loading Package Graph")
            let graph = try await workspace.loadPackageGraph(
                rootInput: root,
                forceResolvedVersions: swiftCommandState.options.resolver.forceResolvedVersions,
                observabilityScope: graphScope
            )
            guard !graphScope.errorsReported else {
                throw ExitCode.failure
            }

            // `getActiveWorkspace(enableAllTraits:)` only enables all traits once the workspace has been created,
            // which happened above.
            let allTraitsWorkspace = try swiftCommandState.getActiveWorkspace(enableAllTraits: true)
            let allTraitsRoot = PackageGraphRootInput(
                packages: root.packages,
                dependencies: root.dependencies,
                traitConfiguration: .enableAllTraits
            )
            // Failures of this attempt are expected and must not fail the command, so they are collected in a
            // separate observability system instead of the command's.
            let errors = ThreadSafeArrayStore<String>()
            let allTraitsScope = ObservabilitySystem({ _, diagnostic in
                if diagnostic.severity == .error {
                    errors.append(diagnostic.message)
                }
            }).topScope
            var reason: String
            do {
                let allTraitsGraph = try await allTraitsWorkspace.loadPackageGraph(
                    rootInput: allTraitsRoot,
                    forceResolvedVersions: true,
                    observabilityScope: allTraitsScope
                )
                if !allTraitsScope.errorsReported {
                    return (allTraitsGraph, allTraitsWorkspace, allTraitsRoot)
                }
                reason = errors.get().first ?? "unknown error"
            } catch {
                reason = errors.get().first ?? error.interpolationDescription
            }
            swiftCommandState.observabilityScope.emit(
                warning: "dependencies used only with traits that are not enabled were not audited, since the package graph with all traits enabled could not be loaded from '\(workspace.location.resolvedVersionsFile.basename)' without changing it: \(reason)"
            )
            return (graph, workspace, root)
        }

        /// The advisory database to query: `--advisory-database`, then the package's configuration, then the
        /// user's configuration, then the default database.
        private static func advisoryDatabaseURL(
            options: AuditOptions,
            workspace: Workspace,
            swiftCommandState: SwiftCommandState
        ) throws -> URL {
            let configured = try Workspace.Configuration.Audit(
                fileSystem: swiftCommandState.fileSystem,
                localAuditFile: workspace.location.localAuditConfigurationFile,
                sharedAuditFile: workspace.location.sharedAuditConfigurationFile
            ).advisoryDatabase
            let value = options.advisoryDatabase ?? configured ?? Self.defaultAdvisoryDatabase
            guard let url = URL(string: value) else {
                throw StringError("invalid advisory database URL '\(value)'")
            }
            return url
        }

        private static func makeRegistryClient(
            workspace: Workspace,
            swiftCommandState: SwiftCommandState
        ) throws -> RegistryClient {
            let configuration = try Workspace.Configuration.Registries(
                fileSystem: swiftCommandState.fileSystem,
                localRegistriesFile: workspace.location.localRegistriesConfigurationFile,
                sharedRegistriesFile: workspace.location.sharedRegistriesConfigurationFile
            ).configuration
            let client = RegistryClient(
                configuration: configuration,
                fingerprintStorage: .none,
                fingerprintCheckingMode: .strict,
                skipSignatureValidation: false,
                signingEntityStorage: .none,
                signingEntityCheckingMode: .strict,
                authorizationProvider: try swiftCommandState.getRegistryAuthorizationProvider(),
                delegate: .none,
                checksumAlgorithm: SHA256()
            )
            // Match the workspace, which uses `--default-registry-url` unless a default registry is configured.
            if client.defaultRegistry == nil, let url = swiftCommandState.options.resolver.defaultRegistryURL {
                client.defaultRegistry = Registry(url: url, supportsAvailability: true)
            }
            return client
        }
    }
}
