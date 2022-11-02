//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import TSCBasic
import SPMBuildCore
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import XCBuildSupport
import Workspace
import Foundation
import PackageModel

import enum TSCUtility.Diagnostics

/// swift-package tool namespace
public struct SwiftPackageTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package",
        _superCommandName: "swift",
        abstract: "Perform operations on Swift packages",
        discussion: "SEE ALSO: swift build, swift run, swift test",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [
            Clean.self,
            PurgeCache.self,
            Reset.self,
            Update.self,
            Describe.self,
            Init.self,
            Format.self,

            APIDiff.self,
            DeprecatedAPIDiff.self,
            DumpSymbolGraph.self,
            DumpPIF.self,
            DumpPackage.self,

            Edit.self,
            Unedit.self,

            Config.self,
            Resolve.self,
            Fetch.self,

            ShowDependencies.self,
            ToolsVersionCommand.self,
            ComputeChecksum.self,
            ArchiveSource.self,
            CompletionTool.self,
            PluginCommand.self,
            
            DefaultCommand.self,
        ]
        + (ProcessInfo.processInfo.environment["SWIFTPM_ENABLE_SNIPPETS"] == "1" ? [Learn.self] : []),
        defaultSubcommand: DefaultCommand.self,
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    var globalOptions: GlobalOptions

    public init() {}

    public static var _errorLabel: String { "error" }
}

extension InitPackage.PackageType: ExpressibleByArgument {}

extension SwiftPackageTool {
    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().clean(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct PurgeCache: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Purge the global repository cache.")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().purgeCache(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct Reset: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache/build directory")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().reset(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct Update: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(name: [.long, .customShort("n")],
              help: "Display the list of dependencies that can be updated")
        var dryRun: Bool = false

        @Argument(help: "The packages to update")
        var packages: [String] = []

        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()

            let changes = try workspace.updateDependencies(
                root: swiftTool.getWorkspaceRoot(),
                packages: packages,
                dryRun: dryRun,
                observabilityScope: swiftTool.observabilityScope
            )

            // try to load the graph which will emit any errors
            if !swiftTool.observabilityScope.errorsReported {
                _ = try workspace.loadPackageGraph(
                    rootInput: swiftTool.getWorkspaceRoot(),
                    observabilityScope: swiftTool.observabilityScope
                )
            }

            if self.dryRun, let changes = changes, let pinsStore = swiftTool.observabilityScope.trap({ try workspace.pinsStore.load() }){
                logPackageChanges(changes: changes, pins: pinsStore)
            }

            if !self.dryRun {
                // Throw if there were errors when loading the graph.
                // The actual errors will be printed before exiting.
                guard !swiftTool.observabilityScope.errorsReported else {
                    throw ExitCode.failure
                }
            }
        }

        private func logPackageChanges(changes: [(PackageReference, Workspace.PackageStateChange)], pins: PinsStore) {
            let changes = changes.filter { $0.1 != .unchanged }

            var report = "\(changes.count) dependenc\(changes.count == 1 ? "y has" : "ies have") changed\(changes.count > 0 ? ":" : ".")"
            for (package, change) in changes {
                let currentVersion = pins.pinsMap[package.identity]?.state.description ?? ""
                switch change {
                case let .added(state):
                    report += "\n"
                    report += "+ \(package.identity) \(state.requirement.prettyPrinted)"
                case let .updated(state):
                    report += "\n"
                    report += "~ \(package.identity) \(currentVersion) -> \(package.identity) \(state.requirement.prettyPrinted)"
                case .removed:
                    report += "\n"
                    report += "- \(package.identity) \(currentVersion)"
                case .unchanged:
                    continue
                }
            }

            print(report)
        }
    }

    struct Describe: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Describe the current package")
        
        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions
        
        @Option(help: "json | text")
        var type: DescribeMode = .text
        
        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            
            guard let packagePath = try swiftTool.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }
            
            let package = try tsc_await {
                workspace.loadRootPackage(
                    at: packagePath,
                    observabilityScope: swiftTool.observabilityScope,
                    completion: $0
                )
            }
            
            try self.describe(package, in: type)
        }
        
        /// Emits a textual description of `package` to `stream`, in the format indicated by `mode`.
        func describe(_ package: Package, in mode: DescribeMode) throws {
            let desc = DescribedPackage(from: package)
            let data: Data
            switch mode {
            case .json:
                let encoder = JSONEncoder.makeWithDefaults()
                encoder.keyEncodingStrategy = .convertToSnakeCase
                data = try encoder.encode(desc)
            case .text:
                var encoder = PlainTextEncoder()
                encoder.formattingOptions = [.prettyPrinted]
                data = try encoder.encode(desc)
            }
            print(String(decoding: data, as: UTF8.self))
        }
        
        enum DescribeMode: String, ExpressibleByArgument {
            /// JSON format (guaranteed to be parsable and stable across time).
            case json
            /// Human readable format (not guaranteed to be parsable).
            case text
        }
    }

    struct Init: SwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions
        
        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Package type: empty | library | executable | system-module | manifest", discussion: """
                empty - Create an empty package
                library - Create a package that contains a library
                executable - Create a package that contains a binary executable
                system-module - Create a package that contains a system module
                manifest - Create a Package.swift file
                """))
        var initMode: InitPackage.PackageType = .library

        @Option(name: .customLong("name"), help: "Provide custom package name")
        var packageName: String?

        func run(_ swiftTool: SwiftTool) throws {
            guard let cwd = swiftTool.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename
            let initPackage = try InitPackage(
                name: packageName,
                packageType: initMode,
                destinationPath: cwd,
                fileSystem: swiftTool.fileSystem
            )
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()
        }
    }

    struct Format: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "_format")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Argument(parsing: .unconditionalRemaining,
                  help: "Pass flag through to the swift-format tool")
        var swiftFormatFlags: [String] = []

        func run(_ swiftTool: SwiftTool) throws {
            // Look for swift-format binary.
            // FIXME: This should be moved to user toolchain.
            let swiftFormatInEnv = lookupExecutablePath(filename: ProcessEnv.vars["SWIFT_FORMAT"])
            guard let swiftFormat = swiftFormatInEnv ?? Process.findExecutable("swift-format") else {
                swiftTool.observabilityScope.emit(error: "Could not find swift-format in PATH or SWIFT_FORMAT")
                throw Diagnostics.fatalError
            }

            // Get the root package.
            let workspace = try swiftTool.getActiveWorkspace()

            guard let packagePath = try swiftTool.getWorkspaceRoot().packages.first else {
                throw StringError("unknown package")
            }

            let package = try tsc_await {
                workspace.loadRootPackage(
                    at: packagePath,
                    observabilityScope: swiftTool.observabilityScope,
                    completion: $0
                )
            }

            // Use the user provided flags or default to formatting mode.
            let formatOptions = swiftFormatFlags.isEmpty
                ? ["--mode", "format", "--in-place", "--parallel"]
                : swiftFormatFlags

            // Process each target in the root package.
            let paths = package.targets.flatMap { target in
                target.sources.paths.filter { file in
                    file.extension == SupportedLanguageExtension.swift.rawValue
                }
            }.map { $0.pathString }

            let args = [swiftFormat.pathString] + formatOptions + [packagePath.pathString] + paths
            print("Running:", args.map{ $0.spm_shellEscaped() }.joined(separator: " "))

            let result = try TSCBasic.Process.popen(arguments: args)
            let output = try (result.utf8Output() + result.utf8stderrOutput())

            if result.exitStatus != .terminated(code: 0) {
                print("Non-zero exit", result.exitStatus)
            }
            if !output.isEmpty {
                print(output)
            }
        }
    }

    struct DeprecatedAPIDiff: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "experimental-api-diff",
                                                        abstract: "Deprecated - use `swift package diagnose-api-breaking-changes` instead",
                                                        shouldDisplay: false)

        @Argument(parsing: .unconditionalRemaining)
        var args: [String] = []

        func run() throws {
            print("`swift package experimental-api-diff` has been renamed to `swift package diagnose-api-breaking-changes`")
            throw ExitCode.failure
        }
    }

    struct APIDiff: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "diagnose-api-breaking-changes",
            abstract: "Diagnose API-breaking changes to Swift modules in a package",
            discussion: """
            The diagnose-api-breaking-changes command can be used to compare the Swift API of \
            a package to a baseline revision, diagnosing any breaking changes which have \
            been introduced. By default, it compares every Swift module from the baseline \
            revision which is part of a library product. For packages with many targets, this \
            behavior may be undesirable as the comparison can be slow. \
            The `--products` and `--targets` options may be used to restrict the scope of \
            the comparison.
            """)

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: """
        The path to a text file containing breaking changes which should be ignored by the API comparison. \
        Each ignored breaking change in the file should appear on its own line and contain the exact message \
        to be ignored (e.g. 'API breakage: func foo() has been removed').
        """)
        var breakageAllowlistPath: AbsolutePath?

        @Argument(help: "The baseline treeish to compare to (e.g. a commit hash, branch name, tag, etc.)")
        var treeish: String

        @Option(parsing: .upToNextOption,
                help: "One or more products to include in the API comparison. If present, only the specified products (and any targets specified using `--targets`) will be compared.")
        var products: [String] = []

        @Option(parsing: .upToNextOption,
                help: "One or more targets to include in the API comparison. If present, only the specified targets (and any products specified using `--products`) will be compared.")
        var targets: [String] = []

        @Option(name: .customLong("baseline-dir"),
                help: "The path to a directory used to store API baseline files. If unspecified, a temporary directory will be used.")
        var overrideBaselineDir: AbsolutePath?

        @Flag(help: "Regenerate the API baseline, even if an existing one is available.")
        var regenerateBaseline: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let apiDigesterPath = try swiftTool.getDestinationToolchain().getSwiftAPIDigester()
            let apiDigesterTool = SwiftAPIDigester(fileSystem: swiftTool.fileSystem, tool: apiDigesterPath)

            let packageRoot = try globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
            let repository = GitRepository(path: packageRoot)
            let baselineRevision = try repository.resolveRevision(identifier: treeish)

            // We turn build manifest caching off because we need the build plan.
            let buildSystem = try swiftTool.createBuildSystem(explicitBuildSystem: .native, cacheBuildManifest: false)

            let packageGraph = try buildSystem.getPackageGraph()
            let modulesToDiff = try determineModulesToDiff(
                packageGraph: packageGraph,
                observabilityScope: swiftTool.observabilityScope
            )

            // Build the current package.
            try buildSystem.build()

            // Dump JSON for the baseline package.
            let baselineDumper = try APIDigesterBaselineDumper(
                baselineRevision: baselineRevision,
                packageRoot: swiftTool.getPackageRoot(),
                buildParameters: try buildSystem.buildPlan.buildParameters,
                apiDigesterTool: apiDigesterTool,
                observabilityScope: swiftTool.observabilityScope
            )

            let baselineDir = try baselineDumper.emitAPIBaseline(
                for: modulesToDiff,
                at: overrideBaselineDir,
                force: regenerateBaseline,
                logLevel: swiftTool.logLevel,
                swiftTool: swiftTool
            )

            let results = ThreadSafeArrayStore<SwiftAPIDigester.ComparisonResult>()
            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: Int(try buildSystem.buildPlan.buildParameters.jobs))
            var skippedModules: Set<String> = []

            for module in modulesToDiff {
                let moduleBaselinePath = baselineDir.appending(component: "\(module).json")
                guard swiftTool.fileSystem.exists(moduleBaselinePath) else {
                    print("\nSkipping \(module) because it does not exist in the baseline")
                    skippedModules.insert(module)
                    continue
                }
                semaphore.wait()
                DispatchQueue.sharedConcurrent.async(group: group) {
                    do {
                        if let comparisonResult = try apiDigesterTool.compareAPIToBaseline(
                            at: moduleBaselinePath,
                            for: module,
                            buildPlan: try buildSystem.buildPlan,
                            except: breakageAllowlistPath
                        ) {
                            results.append(comparisonResult)
                        }
                    } catch {
                        swiftTool.observabilityScope.emit(error: "failed to compare API to baseline: \(error)")
                    }
                    semaphore.signal()
                }
            }

            group.wait()

            let failedModules = modulesToDiff
                .subtracting(skippedModules)
                .subtracting(results.map(\.moduleName))
            for failedModule in failedModules {
                swiftTool.observabilityScope.emit(error: "failed to read API digester output for \(failedModule)")
            }

            for result in results.get() {
                try self.printComparisonResult(result, observabilityScope: swiftTool.observabilityScope)
            }

            guard failedModules.isEmpty && results.get().allSatisfy(\.hasNoAPIBreakingChanges) else {
                throw ExitCode.failure
            }
        }

        private func determineModulesToDiff(packageGraph: PackageGraph, observabilityScope: ObservabilityScope) throws -> Set<String> {
            var modulesToDiff: Set<String> = []
            if products.isEmpty && targets.isEmpty {
                modulesToDiff.formUnion(packageGraph.apiDigesterModules)
            } else {
                for productName in products {
                    guard let product = packageGraph
                            .rootPackages
                            .flatMap(\.products)
                            .first(where: { $0.name == productName }) else {
                        observabilityScope.emit(error: "no such product '\(productName)'")
                        continue
                    }
                    guard product.type.isLibrary else {
                        observabilityScope.emit(error: "'\(productName)' is not a library product")
                        continue
                    }
                    modulesToDiff.formUnion(product.targets.filter { $0.underlyingTarget is SwiftTarget }.map(\.c99name))
                }
                for targetName in targets {
                    guard let target = packageGraph
                            .rootPackages
                            .flatMap(\.targets)
                            .first(where: { $0.name == targetName }) else {
                        observabilityScope.emit(error: "no such target '\(targetName)'")
                        continue
                    }
                    guard target.type == .library else {
                        observabilityScope.emit(error: "'\(targetName)' is not a library target")
                        continue
                    }
                    guard target.underlyingTarget is SwiftTarget else {
                        observabilityScope.emit(error: "'\(targetName)' is not a Swift language target")
                        continue
                    }
                    modulesToDiff.insert(target.c99name)
                }
                guard !observabilityScope.errorsReported else {
                    throw ExitCode.failure
                }
            }
            return modulesToDiff
        }

        private func printComparisonResult(
            _ comparisonResult: SwiftAPIDigester.ComparisonResult,
            observabilityScope: ObservabilityScope
        ) throws {
            for diagnostic in comparisonResult.otherDiagnostics {
                let metadata = try diagnostic.location.map { location -> ObservabilityMetadata in
                    var metadata = ObservabilityMetadata()
                    metadata.fileLocation = .init(
                        try .init(validating: location.filename),
                        line: location.line < Int.max ? Int(location.line) : .none
                    )
                    return metadata
                }

                switch diagnostic.level {
                case .error, .fatal:
                    observabilityScope.emit(error: diagnostic.text, metadata: metadata)
                case .warning:
                    observabilityScope.emit(warning: diagnostic.text, metadata: metadata)
                case .note:
                    observabilityScope.emit(info: diagnostic.text, metadata: metadata)
                case .remark:
                    observabilityScope.emit(info: diagnostic.text, metadata: metadata)
                case .ignored:
                    break
                }
            }

            let moduleName = comparisonResult.moduleName
            if comparisonResult.apiBreakingChanges.isEmpty {
                print("\nNo breaking changes detected in \(moduleName)")
            } else {
                let count = comparisonResult.apiBreakingChanges.count
                print("\n\(count) breaking \(count > 1 ? "changes" : "change") detected in \(moduleName):")
                for change in comparisonResult.apiBreakingChanges {
                    print("  💔 \(change.text)")
                }
            }
        }
    }

    struct DumpSymbolGraph: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Dump Symbol Graph")
        static let defaultMinimumAccessLevel = SymbolGraphExtract.AccessLevel.public

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Pretty-print the output JSON.")
        var prettyPrint = false

        @Flag(help: "Skip members inherited through classes or default implementations.")
        var skipSynthesizedMembers = false

        @Option(help: "Include symbols with this access level or more. Possible values: \(SymbolGraphExtract.AccessLevel.allValueStrings.joined(separator: " | "))")
        var minimumAccessLevel = defaultMinimumAccessLevel

        @Flag(help: "Skip emitting doc comments for members inherited through classes or default implementations.")
        var skipInheritedDocs = false

        @Flag(help: "Add symbols with SPI information to the symbol graph.")
        var includeSPISymbols = false

        func run(_ swiftTool: SwiftTool) throws {
            // Build the current package.
            //
            // We turn build manifest caching off because we need the build plan.
            let buildSystem = try swiftTool.createBuildSystem(explicitBuildSystem: .native, cacheBuildManifest: false)
            try buildSystem.build()

            // Configure the symbol graph extractor.
            let symbolGraphExtractor = try SymbolGraphExtract(
                fileSystem: swiftTool.fileSystem,
                tool: swiftTool.getDestinationToolchain().getSymbolGraphExtract(),
                skipSynthesizedMembers: skipSynthesizedMembers,
                minimumAccessLevel: minimumAccessLevel,
                skipInheritedDocs: skipInheritedDocs,
                includeSPISymbols: includeSPISymbols,
                outputFormat: .json(pretty: prettyPrint)
            )

            // Run the tool once for every library and executable target in the root package.
            let buildPlan = try buildSystem.buildPlan
            let symbolGraphDirectory = buildPlan.buildParameters.dataPath.appending(component: "symbolgraph")
            let targets = try buildSystem.getPackageGraph().rootPackages.flatMap{ $0.targets }.filter{ $0.type == .library || $0.type == .executable }
            for target in targets {
                print("-- Emitting symbol graph for", target.name)
                try symbolGraphExtractor.extractSymbolGraph(
                    target: target,
                    buildPlan: buildPlan,
                    outputDirectory: symbolGraphDirectory,
                    verboseOutput: swiftTool.logLevel <= .info
                )
            }

            print("Files written to", symbolGraphDirectory.pathString)
        }
    }

    struct DumpPackage: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print parsed Package.swift as JSON")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            let root = try swiftTool.getWorkspaceRoot()

            let rootManifests = try temp_await {
                workspace.loadRootManifests(
                    packages: root.packages,
                    observabilityScope: swiftTool.observabilityScope,
                    completion: $0
                )
            }
            guard let rootManifest = rootManifests.values.first else {
                throw StringError("invalid manifests at \(root.packages)")
            }

            let encoder = JSONEncoder.makeWithDefaults()
            encoder.userInfo[Manifest.dumpPackageKey] = true

            let jsonData = try encoder.encode(rootManifest)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print(jsonString)
        }
    }

    struct DumpPIF: SwiftCommand {
        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Preserve the internal structure of PIF")
        var preserveStructure: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph()
            let pif = try PIFBuilder.generatePIF(
                buildParameters: swiftTool.buildParameters(),
                packageGraph: graph,
                fileSystem: swiftTool.fileSystem,
                observabilityScope: swiftTool.observabilityScope,
                preservePIFModelStructure: preserveStructure)
            print(pif)
        }

        var toolWorkspaceConfiguration: ToolWorkspaceConfiguration {
            return .init(wantsMultipleTestProducts: true)
        }
    }

    struct Edit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a package in editable mode")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The revision to edit", transform: { Revision(identifier: $0) })
        var revision: Revision?

        @Option(name: .customLong("branch"), help: "The branch to create")
        var checkoutBranch: String?

        @Option(help: "Create or use the checkout at this path")
        var path: AbsolutePath?

        @Argument(help: "The name of the package to edit")
        var packageName: String

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.resolve()
            let workspace = try swiftTool.getActiveWorkspace()

            // Put the dependency in edit mode.
            workspace.edit(
                packageName: packageName,
                path: path,
                revision: revision,
                checkoutBranch: checkoutBranch,
                observabilityScope: swiftTool.observabilityScope
            )
        }
    }

    struct Unedit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a package from editable mode")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(name: .customLong("force"),
              help: "Unedit the package even if it has uncommited and unpushed changes")
        var shouldForceRemove: Bool = false

        @Argument(help: "The name of the package to unedit")
        var packageName: String

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.resolve()
            let workspace = try swiftTool.getActiveWorkspace()

            try workspace.unedit(
                packageName: packageName,
                forceRemove: shouldForceRemove,
                root: swiftTool.getWorkspaceRoot(),
                observabilityScope: swiftTool.observabilityScope
            )
        }
    }

    struct ShowDependencies: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the resolved dependency graph")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "text | dot | json | flatlist")
        var format: ShowDependenciesMode = .text

        @Option(name: [.long, .customShort("o") ],
                help: "The absolute or relative path to output the resolved dependency graph.")
        var outputPath: AbsolutePath?

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph()
            // command's result output goes on stdout
            // ie "swift package show-dependencies" should output to stdout
            let stream: OutputByteStream = try outputPath.map { try LocalFileOutputByteStream($0) } ?? TSCBasic.stdoutStream
            Self.dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: format, on: stream)
        }

        static func dumpDependenciesOf(rootPackage: ResolvedPackage, mode: ShowDependenciesMode, on stream: OutputByteStream) {
            let dumper: DependenciesDumper
            switch mode {
            case .text:
                dumper = PlainTextDumper()
            case .dot:
                dumper = DotDumper()
            case .json:
                dumper = JSONDumper()
            case .flatlist:
                dumper = FlatListDumper()
            }
            dumper.dump(dependenciesOf: rootPackage, on: stream)
            stream.flush()
        }

        enum ShowDependenciesMode: String, RawRepresentable, CustomStringConvertible, ExpressibleByArgument {
            case text, dot, json, flatlist

            public init?(rawValue: String) {
                switch rawValue.lowercased() {
                case "text":
                   self = .text
                case "dot":
                   self = .dot
                case "json":
                   self = .json
                case "flatlist":
                    self = .flatlist
                default:
                    return nil
                }
            }

            public var description: String {
                switch self {
                case .text: return "text"
                case .dot: return "dot"
                case .json: return "json"
                case .flatlist: return "flatlist"
                }
            }
        }
    }

    struct ToolsVersionCommand: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "tools-version",
            abstract: "Manipulate tools version of the current package")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(help: "Set tools version of package to the current tools version in use")
        var setCurrent: Bool = false

        @Option(help: "Set tools version of package to the given value")
        var set: String?

        enum ToolsVersionMode {
            case display
            case set(String)
            case setCurrent
        }

        var toolsVersionMode: ToolsVersionMode {
            // TODO: enforce exclusivity
            if let set = set {
                return .set(set)
            } else if setCurrent {
                return .setCurrent
            } else {
                return .display
            }
        }

        func run(_ swiftTool: SwiftTool) throws {
            let pkg = try swiftTool.getPackageRoot()

            switch toolsVersionMode {
            case .display:
                let manifestPath = try ManifestLoader.findManifest(packagePath: pkg, fileSystem: swiftTool.fileSystem, currentToolsVersion: .current)
                let version = try ToolsVersionParser.parse(manifestPath: manifestPath, fileSystem: swiftTool.fileSystem)
                print("\(version)")

            case .set(let value):
                guard let toolsVersion = ToolsVersion(string: value) else {
                    // FIXME: Probably lift this error definition to ToolsVersion.
                    throw ToolsVersionParser.Error.malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt(value)))
                }
                try ToolsVersionSpecificationWriter.rewriteSpecification(
                    manifestDirectory: pkg,
                    toolsVersion: toolsVersion,
                    fileSystem: swiftTool.fileSystem
                )

            case .setCurrent:
                // Write the tools version with current version but with patch set to zero.
                // We do this to avoid adding unnecessary constraints to patch versions, if
                // the package really needs it, they can do it using --set option.
                try ToolsVersionSpecificationWriter.rewriteSpecification(
                    manifestDirectory: pkg,
                    toolsVersion: ToolsVersion.current.zeroedPatch,
                    fileSystem: swiftTool.fileSystem
                )
            }
        }
    }

    struct ComputeChecksum: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute the checksum for a binary artifact.")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Argument(help: "The absolute or relative path to the binary artifact")
        var path: AbsolutePath

        func run(_ swiftTool: SwiftTool) throws {
            let binaryArtifactsManager = try Workspace.BinaryArtifactsManager(
                fileSystem: swiftTool.fileSystem,
                authorizationProvider: swiftTool.getAuthorizationProvider(),
                hostToolchain: swiftTool.getHostToolchain(),
                checksumAlgorithm: SHA256(),
                customHTTPClient: .none,
                customArchiver: .none,
                delegate: .none
            )
            let checksum = try binaryArtifactsManager.checksum(forBinaryArtifactAt: path)
            print(checksum)
        }
    }

    struct ArchiveSource: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "archive-source",
            abstract: "Create a source archive for the package"
        )

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(
            name: [.short, .long],
            help: "The absolute or relative path for the generated source archive"
        )
        var output: AbsolutePath?

        func run(_ swiftTool: SwiftTool) throws {
            let packageRoot = try globalOptions.locations.packageDirectory ?? swiftTool.getPackageRoot()
            let repository = GitRepository(path: packageRoot)

            let destination: AbsolutePath
            if let output = output {
                destination = output
            } else {
                let graph = try swiftTool.loadPackageGraph()
                let packageName = graph.rootPackages[0].manifest.displayName // TODO: use identity instead?
                destination = packageRoot.appending(component: "\(packageName).zip")
            }

            try repository.archive(to: destination)

            if destination.isDescendantOfOrEqual(to: packageRoot) {
                let relativePath = destination.relative(to: packageRoot)
                print("Created \(relativePath.pathString)")
            } else {
                print("Created \(destination.pathString)")
            }
        }
    }
    
    struct PluginCommand: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "plugin",
            abstract: "Invoke a command plugin or perform other actions on command plugins"
        )

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Flag(name: .customLong("list"),
              help: "List the available command plugins")
        var listCommands: Bool = false

        struct PluginOptions: ParsableArguments {
            @Flag(name: .customLong("allow-writing-to-package-directory"),
                  help: "Allow the plugin to write to the package directory")
            var allowWritingToPackageDirectory: Bool = false

            @Option(name: .customLong("allow-writing-to-directory"),
                    help: "Allow the plugin to write to an additional directory")
            var additionalAllowedWritableDirectories: [String] = []
        }

        @OptionGroup()
        var pluginOptions: PluginOptions

        @Argument(help: "Verb of the command plugin to invoke")
        var command: String = ""

        @Argument(parsing: .unconditionalRemaining,
                  help: "Arguments to pass to the command plugin")
        var arguments: [String] = []

        func run(_ swiftTool: SwiftTool) throws {
            // Check for a missing plugin command verb.
            if command == "" && !listCommands {
                throw ValidationError("Missing expected plugin command")
            }

            // Load the workspace and resolve the package graph.
            let packageGraph = try swiftTool.loadPackageGraph()

            // List the available plugins, if asked to.
            if listCommands {
                let allPlugins = PluginCommand.availableCommandPlugins(in: packageGraph)
                for plugin in allPlugins.sorted(by: { $0.name < $1.name }) {
                    guard case .command(let intent, _) = plugin.capability else { return }
                    var line = "‘\(intent.invocationVerb)’ (plugin ‘\(plugin.name)’"
                    if let package = packageGraph.packages.first(where: { $0.targets.contains(where: { $0.name == plugin.name }) }) {
                        line +=  " in package ‘\(package.manifest.displayName)’"
                    }
                    line += ")"
                    print(line)
                }
                return
            }
            
            swiftTool.observabilityScope.emit(info: "Finding plugin for command ‘\(command)’")
            let matchingPlugins = PluginCommand.findPlugins(matching: command, in: packageGraph)

            // Complain if we didn't find exactly one.
            if matchingPlugins.isEmpty {
                throw ValidationError("No command plugins found for ‘\(command)’")
            }
            else if matchingPlugins.count > 1 {
                throw ValidationError("\(matchingPlugins.count) plugins found for ‘\(command)’")
            }
            
            // At this point we know we found exactly one command plugin, so we run it. In SwiftPM CLI, we have only one root package.
            try PluginCommand.run(
                plugin: matchingPlugins[0],
                package: packageGraph.rootPackages[0],
                packageGraph: packageGraph,
                options: pluginOptions,
                arguments: arguments,
                swiftTool: swiftTool)
        }
        
        static func run(
            plugin: PluginTarget,
            package: ResolvedPackage,
            packageGraph: PackageGraph,
            options: PluginOptions,
            arguments: [String],
            swiftTool: SwiftTool
        ) throws {
            swiftTool.observabilityScope.emit(info: "Running command plugin \(plugin) on package \(package) with options \(options) and arguments \(arguments)")
            
            // The `plugins` directory is inside the workspace's main data directory, and contains all temporary files related to this plugin in the workspace.
            let pluginsDir = try swiftTool.getActiveWorkspace().location.pluginWorkingDirectory.appending(component: plugin.name)

            // The `cache` directory is in the plugin’s directory and is where the plugin script runner caches compiled plugin binaries and any other derived information for this plugin.
            let pluginScriptRunner = try swiftTool.getPluginScriptRunner(
                customPluginsDir: pluginsDir
            )

            // The `outputs` directory contains subdirectories for each combination of package and command plugin. Each usage of a plugin has an output directory that is writable by the plugin, where it can write additional files, and to which it can configure tools to write their outputs, etc.
            let outputDir = pluginsDir.appending(component: "outputs")

            // Determine the set of directories under which plugins are allowed to write. We always include the output directory.
            var writableDirectories = [outputDir]
            if options.allowWritingToPackageDirectory {
                writableDirectories.append(package.path)
            }
            else {
                // If the plugin requires write permission but it wasn't provided, we ask the user for approval.
                if case .command(_, let permissions) = plugin.capability {
                    for case PluginPermission.writeToPackageDirectory(let reason) in permissions {
                        let problem = "Plugin ‘\(plugin.name)’ wants permission to write to the package directory."
                        let reason = "Stated reason: “\(reason)”."
                        if swiftTool.outputStream.isTTY {
                            // We can ask the user directly, so we do so.
                            let query = "Allow this plugin to write to the package directory?"
                            swiftTool.outputStream.write("\(problem)\n\(reason)\n\(query) (yes/no) ".utf8)
                            swiftTool.outputStream.flush()
                            let answer = readLine(strippingNewline: true)
                            // Throw an error if we didn't get permission.
                            if answer?.lowercased() != "yes" {
                                throw ValidationError("Plugin was denied permission to write to the package directory.")
                            }
                            // Otherwise append the directory to the list of allowed ones.
                            writableDirectories.append(package.path)
                        }
                        else {
                            // We can't ask the user, so emit an error suggesting passing the flag.
                            let remedy = "Use `--allow-writing-to-package-directory` to allow this."
                            throw ValidationError([problem, reason, remedy].joined(separator: "\n"))
                        }
                    }
                }
            }
            for pathString in options.additionalAllowedWritableDirectories {
                writableDirectories.append(try AbsolutePath(validating: pathString, relativeTo: swiftTool.originalWorkingDirectory))
            }

            // Make sure that the package path is read-only unless it's covered by any of the explicitly writable directories.
            let readOnlyDirectories = writableDirectories.contains{ package.path.isDescendantOfOrEqual(to: $0) } ? [] : [package.path]

            // Use the directory containing the compiler as an additional search directory, and add the $PATH.
            let toolSearchDirs = [try swiftTool.getDestinationToolchain().swiftCompilerPath.parentDirectory]
                + getEnvSearchPaths(pathString: ProcessEnv.path, currentWorkingDirectory: .none)
            
            // Build or bring up-to-date any executable host-side tools on which this plugin depends. Add them and any binary dependencies to the tool-names-to-path map.
            var toolNamesToPaths: [String: AbsolutePath] = [:]
            for dep in try plugin.accessibleTools(packageGraph: packageGraph, fileSystem: swiftTool.fileSystem, environment: try swiftTool.buildParameters().buildEnvironment, for: try pluginScriptRunner.hostTriple) {
                let buildSystem = try swiftTool.createBuildSystem(explicitBuildSystem: .native, cacheBuildManifest: false)
                switch dep {
                case .builtTool(let name, _):
                    // Build the product referenced by the tool, and add the executable to the tool map. Product dependencies are not supported within a package, so if the tool happens to be from the same package, we instead find the executable that corresponds to the product. There is always one, because of autogeneration of implicit executables with the same name as the target if there isn't an explicit one.
                    try buildSystem.build(subset: .product(name))
                    if let builtTool = try buildSystem.buildPlan.buildProducts.first(where: { $0.product.name == name}) {
                        toolNamesToPaths[name] = builtTool.binaryPath
                    }
                case .vendedTool(let name, let path):
                    toolNamesToPaths[name] = path
                }
            }
            
            // Set up a delegate to handle callbacks from the command plugin.
            let pluginDelegate = PluginDelegate(swiftTool: swiftTool, plugin: plugin)
            let delegateQueue = DispatchQueue(label: "plugin-invocation")

            // Run the command plugin.
            let buildEnvironment = try swiftTool.buildParameters().buildEnvironment
            let _ = try tsc_await { plugin.invoke(
                action: .performCommand(package: package, arguments: arguments),
                buildEnvironment: buildEnvironment,
                scriptRunner: pluginScriptRunner,
                workingDirectory: swiftTool.originalWorkingDirectory,
                outputDirectory: outputDir,
                toolSearchDirectories: toolSearchDirs,
                toolNamesToPaths: toolNamesToPaths,
                writableDirectories: writableDirectories,
                readOnlyDirectories: readOnlyDirectories,
                fileSystem: swiftTool.fileSystem,
                observabilityScope: swiftTool.observabilityScope,
                callbackQueue: delegateQueue,
                delegate: pluginDelegate,
                completion: $0) }
            
            // TODO: We should also emit a final line of output regarding the result.
        }

        static func availableCommandPlugins(in graph: PackageGraph) -> [PluginTarget] {
            return graph.allTargets.compactMap{ $0.underlyingTarget as? PluginTarget }
        }

        static func findPlugins(matching verb: String, in graph: PackageGraph) -> [PluginTarget] {
            // Find and return the command plugins that match the command.
            return Self.availableCommandPlugins(in: graph).filter {
                // Filter out any non-command plugins and any whose verb is different.
                guard case .command(let intent, _) = $0.capability else { return false }
                return verb == intent.invocationVerb
            }
        }
    }
}

extension PluginCommandIntent {
    var invocationVerb: String {
        switch self {
        case .documentationGeneration:
            return "generate-documentation"
        case .sourceCodeFormatting:
            return "format-source-code"
        case .custom(let verb, _):
            return verb
        }
    }
}

extension SwiftPackageTool {
    // This command is the default when no other subcommand is passed. It is not shown in the help and is never invoked directly.
    struct DefaultCommand: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: nil,
            shouldDisplay: false)

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var pluginOptions: PluginCommand.PluginOptions

        @Argument(parsing: .unconditionalRemaining)
        var remaining: [String] = []

        func run(_ swiftTool: SwiftTool) throws {
            // See if have a possible plugin command.
            guard let command = remaining.first else {
                print(SwiftPackageTool.helpMessage())
                return
            }
            
            // Check for edge cases and unknown options to match the behavior in the absence of plugins.
            if command.isEmpty {
                throw ValidationError("Unknown argument '\(command)'")
            }
            else if command.starts(with: "-") {
                throw ValidationError("Unknown option '\(command)'")
            }

            // Otherwise see if we can find a plugin.
            
            // We first have to try to resolve the package graph to find any plugins.
            // TODO: Ideally we should only resolve plugin dependencies, if we had a way of distinguishing them.
            let packageGraph = try swiftTool.loadPackageGraph()

            // Otherwise find all plugins that match the command verb.
            swiftTool.observabilityScope.emit(info: "Finding plugin for command '\(command)'")
            let matchingPlugins = PluginCommand.findPlugins(matching: command, in: packageGraph)

            // Complain if we didn't find exactly one. We have to formulate the error message taking into account that this might be a misspelled subcommand.
            if matchingPlugins.isEmpty {
                throw ValidationError("Unknown subcommand or plugin name '\(command)'")
            }
            else if matchingPlugins.count > 1 {
                throw ValidationError("\(matchingPlugins.count) plugins found for '\(command)'")
            }
            
            // At this point we know we found exactly one command plugin, so we run it.
            try PluginCommand.run(
                plugin: matchingPlugins[0],
                package: packageGraph.rootPackages[0],
                packageGraph: packageGraph,
                options: pluginOptions,
                arguments: Array( remaining.dropFirst()),
                swiftTool: swiftTool)
        }
    }
}

extension SwiftPackageTool {
    struct Config: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manipulate configuration of the package",
            subcommands: [SetMirror.self, UnsetMirror.self, GetMirror.self])
    }
}

extension SwiftPackageTool.Config {
    struct SetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a mirror for a dependency")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        @Option(help: "The mirror url")
        var mirrorURL: String

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = self.packageURL ?? self.originalURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                mirrors.set(mirrorURL: self.mirrorURL, forURL: originalURL)
            }
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        @Option(help: "The mirror url")
        var mirrorURL: String?

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalOrMirrorURL = self.packageURL ?? self.originalURL ?? self.mirrorURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url or --mirror-url"))
                throw ExitCode.failure
            }

            try config.applyLocal { mirrors in
                try mirrors.unset(originalOrMirrorURL: originalOrMirrorURL)
            }
        }
    }

    struct GetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print mirror configuration for the given package dependency")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Option(help: "The package dependency url")
        var packageURL: String?

        @Option(help: "The original url")
        var originalURL: String?

        func run(_ swiftTool: SwiftTool) throws {
            let config = try getMirrorsConfig(swiftTool)

            if self.packageURL != nil {
                swiftTool.observabilityScope.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = self.packageURL ?? self.originalURL else {
                swiftTool.observabilityScope.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            if let mirror = config.mirrors.mirrorURL(for: originalURL) {
                print(mirror)
            } else {
                stderrStream <<< "not found\n"
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }

    static func getMirrorsConfig(_ swiftTool: SwiftTool) throws -> Workspace.Configuration.Mirrors {
        let workspace = try swiftTool.getActiveWorkspace()
        return try .init(
            fileSystem: swiftTool.fileSystem,
            localMirrorsFile: workspace.location.localMirrorsConfigurationFile,
            sharedMirrorsFile: workspace.location.sharedMirrorsConfigurationFile
        )
    }
}

extension SwiftPackageTool {
    struct ResolveOptions: ParsableArguments {
        @Option(help: "The version to resolve at", transform: { Version($0) })
        var version: Version?

        @Option(help: "The branch to resolve at")
        var branch: String?

        @Option(help: "The revision to resolve at")
        var revision: String?

        @Argument(help: "The name of the package to resolve")
        var packageName: String?
    }

    struct Resolve: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Resolve package dependencies")

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftTool: SwiftTool) throws {
            // If a package is provided, use that to resolve the dependencies.
            if let packageName = resolveOptions.packageName {
                let workspace = try swiftTool.getActiveWorkspace()
                try workspace.resolve(
                    packageName: packageName,
                    root: swiftTool.getWorkspaceRoot(),
                    version: resolveOptions.version,
                    branch: resolveOptions.branch,
                    revision: resolveOptions.revision,
                    observabilityScope: swiftTool.observabilityScope
                )
                if swiftTool.observabilityScope.errorsReported {
                    throw ExitCode.failure
                }
            } else {
                // Otherwise, run a normal resolve.
                try swiftTool.resolve()
            }
        }
    }

    struct Fetch: SwiftCommand {
        static let configuration = CommandConfiguration(shouldDisplay: false)

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftTool: SwiftTool) throws {
            swiftTool.observabilityScope.emit(warning: "'fetch' command is deprecated; use 'resolve' instead")

            let resolveCommand = Resolve(globalOptions: _globalOptions, resolveOptions: _resolveOptions)
            try resolveCommand.run(swiftTool)
        }
    }
}

extension SwiftPackageTool {
    struct CompletionTool: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Completion tool (for shell completions)"
        )

        enum Mode: String, CaseIterable, ExpressibleByArgument {
            case generateBashScript = "generate-bash-script"
            case generateZshScript = "generate-zsh-script"
            case generateFishScript = "generate-fish-script"
            case listDependencies = "list-dependencies"
            case listExecutables = "list-executables"
            case listSnippets = "list-snippets"
        }

        /// A dummy version of the root `swift` command, to act as a parent
        /// for all the subcommands.
        fileprivate struct SwiftCommand: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "swift",
                abstract: "The Swift compiler",
                subcommands: [
                    SwiftRunTool.self,
                    SwiftBuildTool.self,
                    SwiftTestTool.self,
                    SwiftPackageTool.self,
                ]
            )
        }

        @OptionGroup(_hiddenFromHelp: true)
        var globalOptions: GlobalOptions

        @Argument(help: "generate-bash-script | generate-zsh-script |\ngenerate-fish-script | list-dependencies | list-executables")
        var mode: Mode

        func run(_ swiftTool: SwiftTool) throws {
            switch mode {
            case .generateBashScript:
                let script = SwiftCommand.completionScript(for: .bash)
                print(script)
            case .generateZshScript:
                let script = SwiftCommand.completionScript(for: .zsh)
                print(script)
            case .generateFishScript:
                let script = SwiftCommand.completionScript(for: .fish)
                print(script)
            case .listDependencies:
                let graph = try swiftTool.loadPackageGraph()
                // command's result output goes on stdout
                // ie "swift package list-dependencies" should output to stdout
                ShowDependencies.dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: .flatlist, on: TSCBasic.stdoutStream)
            case .listExecutables:
                let graph = try swiftTool.loadPackageGraph()
                let package = graph.rootPackages[0].underlyingPackage
                let executables = package.targets.filter { $0.type == .executable }
                for executable in executables {
                    print(executable.name)
                }
            case .listSnippets:
                let graph = try swiftTool.loadPackageGraph()
                let package = graph.rootPackages[0].underlyingPackage
                let executables = package.targets.filter { $0.type == .snippet }
                for executable in executables {
                    print(executable.name)
                }
            }
        }
    }
}

extension SwiftPackageTool {
    struct Learn: SwiftCommand {

        @OptionGroup()
        var globalOptions: GlobalOptions

        static let configuration = CommandConfiguration(abstract: "Learn about Swift and this package")

        func files(fileSystem: FileSystem, in directory: AbsolutePath, fileExtension: String? = nil) throws -> [AbsolutePath] {
            guard fileSystem.isDirectory(directory) else {
                return []
            }

            let files = try fileSystem.getDirectoryContents(directory)
                .map { try AbsolutePath(validating: $0, relativeTo: directory) }
                .filter { fileSystem.isFile($0) }

            guard let fileExtension = fileExtension else {
                return files
            }

            return files.filter { $0.extension == fileExtension }
        }

        func subdirectories(fileSystem: FileSystem, in directory: AbsolutePath) throws -> [AbsolutePath] {
            guard fileSystem.isDirectory(directory) else {
                return []
            }
            return try fileSystem.getDirectoryContents(directory)
                .map { try AbsolutePath(validating: $0, relativeTo: directory) }
                .filter { fileSystem.isDirectory($0) }
        }

        func loadSnippetsAndSnippetGroups(fileSystem: FileSystem, from package: ResolvedPackage) throws -> [SnippetGroup] {
            let snippetsDirectory = package.path.appending(component: "Snippets")
            guard fileSystem.isDirectory(snippetsDirectory) else {
                return []
            }

            let topLevelSnippets = try files(fileSystem: fileSystem, in: snippetsDirectory, fileExtension: "swift")
                .map { try Snippet(parsing: $0) }

            let topLevelSnippetGroup = SnippetGroup(name: "Getting Started",
                                                    baseDirectory: snippetsDirectory,
                                                    snippets: topLevelSnippets,
                                                    explanation: "")

            let subdirectoryGroups = try subdirectories(fileSystem: fileSystem, in: snippetsDirectory)
                .map { subdirectory -> SnippetGroup in
                    let snippets = try files(fileSystem: fileSystem, in: subdirectory, fileExtension: "swift")
                        .map { try Snippet(parsing: $0) }

                    let explanationFile = subdirectory.appending(component: "Explanation.md")

                    let snippetGroupExplanation: String
                    if fileSystem.isFile(explanationFile) {
                        snippetGroupExplanation = try String(contentsOf: explanationFile.asURL)
                    } else {
                        snippetGroupExplanation = ""
                    }

                    return SnippetGroup(name: subdirectory.basename,
                                        baseDirectory: subdirectory,
                                        snippets: snippets,
                                        explanation: snippetGroupExplanation)
                }

            let snippetGroups = [topLevelSnippetGroup] + subdirectoryGroups.sorted {
                $0.baseDirectory.basename < $1.baseDirectory.basename
            }

            return snippetGroups.filter { !$0.snippets.isEmpty }
        }

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph()
            let package = graph.rootPackages[0]
            print(package.products.map { $0.description })

            let snippetGroups = try loadSnippetsAndSnippetGroups(fileSystem: swiftTool.fileSystem, from: package)

            var cardStack = CardStack(package: package, snippetGroups: snippetGroups, swiftTool: swiftTool)

            cardStack.run()
        }
    }
}

private extension Basics.Diagnostic {
    static var missingRequiredSubcommand: Self {
        .error("missing required subcommand; use --help to list available subcommands")
    }

    static func missingRequiredArg(_ argument: String) -> Self {
        .error("missing required argument \(argument)")
    }
}
