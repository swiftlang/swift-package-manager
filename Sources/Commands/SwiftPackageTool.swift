/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import TSCBasic
import SPMBuildCore
import Build
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import Xcodeproj
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
        version: SwiftVersion.currentVersion.completeDisplayString,
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
            GenerateXcodeProject.self,
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
    var swiftOptions: SwiftToolOptions

    public init() {}

    public static var _errorLabel: String { "error" }
}

extension InitPackage.PackageType: ExpressibleByArgument {}

extension SwiftPackageTool {
    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().clean(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct PurgeCache: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Purge the global repository cache.")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().purgeCache(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct Reset: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache/build directory")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().reset(observabilityScope: swiftTool.observabilityScope)
        }
    }

    struct Update: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions
        
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
        var swiftOptions: SwiftToolOptions

        @Option(name: .customLong("type"), help: "Package type: empty | library | executable | system-module | manifest")
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
        var swiftOptions: SwiftToolOptions

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

            let result = try Process.popen(arguments: args)
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
        var swiftOptions: SwiftToolOptions

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
            let apiDigesterPath = try swiftTool.getToolchain().getSwiftAPIDigester()
            let apiDigesterTool = SwiftAPIDigester(fileSystem: swiftTool.fileSystem, tool: apiDigesterPath)

            let packageRoot = try swiftOptions.packagePath ?? swiftTool.getPackageRoot()
            let repository = GitRepository(path: packageRoot)
            let baselineRevision = try repository.resolveRevision(identifier: treeish)

            // We turn build manifest caching off because we need the build plan.
            let buildOp = try swiftTool.createBuildOperation(cacheBuildManifest: false)

            let packageGraph = try buildOp.getPackageGraph()
            let modulesToDiff = try determineModulesToDiff(
                packageGraph: packageGraph,
                observabilityScope: swiftTool.observabilityScope
            )

            // Build the current package.
            try buildOp.build()

            // Dump JSON for the baseline package.
            let baselineDumper = try APIDigesterBaselineDumper(
                baselineRevision: baselineRevision,
                packageRoot: swiftTool.getPackageRoot(),
                buildParameters: buildOp.buildParameters,
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
            let semaphore = DispatchSemaphore(value: Int(buildOp.buildParameters.jobs))
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
                    if let comparisonResult = apiDigesterTool.compareAPIToBaseline(
                        at: moduleBaselinePath,
                        for: module,
                        buildPlan: buildOp.buildPlan!,
                        except: breakageAllowlistPath
                    ) {
                        results.append(comparisonResult)
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
                self.printComparisonResult(result, observabilityScope: swiftTool.observabilityScope)
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
        ) {
            for diagnostic in comparisonResult.otherDiagnostics {
                let metadata = diagnostic.location.map { location -> ObservabilityMetadata in
                    var metadata = ObservabilityMetadata()
                    metadata.fileLocation = .init(
                        .init(location.filename),
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
        var swiftOptions: SwiftToolOptions

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
            let buildOp = try swiftTool.createBuildOperation(cacheBuildManifest: false)
            try buildOp.build()

            // Configure the symbol graph extractor.
            let symbolGraphExtractor = try SymbolGraphExtract(
                fileSystem: swiftTool.fileSystem,
                tool: swiftTool.getToolchain().getSymbolGraphExtract(),
                skipSynthesizedMembers: skipSynthesizedMembers,
                minimumAccessLevel: minimumAccessLevel,
                skipInheritedDocs: skipInheritedDocs,
                includeSPISymbols: includeSPISymbols)

            // Run the tool once for every library and executable target in the root package.
            let buildPlan = buildOp.buildPlan!
            let symbolGraphDirectory = buildPlan.buildParameters.dataPath.appending(component: "symbolgraph")
            let targets = buildPlan.graph.rootPackages.flatMap{ $0.targets }.filter{ $0.type == .library || $0.type == .executable }
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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

        @Flag(help: "Preserve the internal structure of PIF")
        var preserveStructure: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph(createMultipleTestProducts: true)
            let parameters = try PIFBuilderParameters(swiftTool.buildParameters())
            let builder = PIFBuilder(
                graph: graph,
                parameters: parameters,
                fileSystem: swiftTool.fileSystem,
                observabilityScope: swiftTool.observabilityScope
            )
            let pif = try builder.generatePIF(preservePIFModelStructure: preserveStructure)
            print(pif)
        }
    }

    struct Edit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a package in editable mode")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
                let toolsVersionLoader = ToolsVersionLoader()
                let version = try toolsVersionLoader.load(at: pkg, fileSystem: swiftTool.fileSystem)
                print("\(version)")

            case .set(let value):
                guard let toolsVersion = ToolsVersion(string: value) else {
                    // FIXME: Probably lift this error definition to ToolsVersion.
                    throw ToolsVersionLoader.Error.malformedToolsVersionSpecification(.versionSpecifier(.isMisspelt(value)))
                }
                try rewriteToolsVersionSpecification(toDefaultManifestIn: pkg, specifying: toolsVersion, fileSystem: swiftTool.fileSystem)

            case .setCurrent:
                // Write the tools version with current version but with patch set to zero.
                // We do this to avoid adding unnecessary constraints to patch versions, if
                // the package really needs it, they can do it using --set option.
                try rewriteToolsVersionSpecification(
                    toDefaultManifestIn: pkg, specifying: ToolsVersion.currentToolsVersion.zeroedPatch, fileSystem: swiftTool.fileSystem)
            }
        }
    }

    struct ComputeChecksum: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute the checksum for a binary artifact.")

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @Argument(help: "The absolute or relative path to the binary artifact")
        var path: AbsolutePath

        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            let checksum = try workspace.checksum(forBinaryArtifactAt: path)
            print(checksum)
        }
    }

    struct ArchiveSource: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "archive-source",
            abstract: "Create a source archive for the package"
        )

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @Option(
            name: [.short, .long],
            help: "The absolute or relative path for the generated source archive"
        )
        var output: AbsolutePath?

        func run(_ swiftTool: SwiftTool) throws {
            let packageRoot = try swiftOptions.packagePath ?? swiftTool.getPackageRoot()
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
        var swiftOptions: SwiftToolOptions

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
                options: pluginOptions,
                arguments: arguments,
                swiftTool: swiftTool)
        }
        
        static func run(
            plugin: PluginTarget,
            package: ResolvedPackage,
            options: PluginOptions,
            arguments: [String],
            swiftTool: SwiftTool
        ) throws {
            swiftTool.observabilityScope.emit(info: "Running command plugin \(plugin) on package \(package) with options \(options) and arguments \(arguments)")
            
            // The `plugins` directory is inside the workspace's main data directory, and contains all temporary files related to this plugin in the workspace.
            let pluginsDir = try swiftTool.getActiveWorkspace().location.pluginWorkingDirectory.appending(component: plugin.name)

            // The `cache` directory is in the plugin’s directory and is where the plugin script runner caches compiled plugin binaries and any other derived information for this plugin.
            let pluginScriptRunner = DefaultPluginScriptRunner(
                fileSystem: swiftTool.fileSystem,
                cacheDir: pluginsDir.appending(component: "cache"),
                toolchain: try swiftTool.getToolchain().configuration,
                enableSandbox: !swiftTool.options.shouldDisableSandbox)

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
                        // TODO: Ask for approval here if connected to TTY; only emit an error if not.
                        throw ValidationError("Plugin ‘\(plugin.name)’ needs permission to write to the package directory (stated reason: “\(reason)”)")
                    }
                }
            }
            for pathString in options.additionalAllowedWritableDirectories {
                writableDirectories.append(AbsolutePath(pathString, relativeTo: swiftTool.originalWorkingDirectory))
            }

            // Make sure that the package path is read-only unless it's covered by any of the explicitly writable directories.
            let readOnlyDirectories = writableDirectories.contains{ package.path.isDescendantOfOrEqual(to: $0) } ? [] : [package.path]

            // Use the directory containing the compiler as an additional search directory, and add the $PATH.
            let toolSearchDirs = [try swiftTool.getToolchain().swiftCompilerPath.parentDirectory]
                + getEnvSearchPaths(pathString: ProcessEnv.path, currentWorkingDirectory: .none)
            
            // Build or bring up-to-date any executable host-side tools on which this plugin depends. Add them and any binary dependencies to the tool-names-to-path map.
            var toolNamesToPaths: [String: AbsolutePath] = [:]
            for dep in plugin.dependencies {
                let buildOperation = try swiftTool.createBuildOperation(cacheBuildManifest: false)
                switch dep {
                case .product(let productRef, _):
                    // Build the product referenced by the tool, and add the executable to the tool map.
                    try buildOperation.build(subset: .product(productRef.name))
                    if let builtTool = buildOperation.buildPlan?.buildProducts.first(where: { $0.product.name == productRef.name}) {
                        toolNamesToPaths[productRef.name] = builtTool.binary
                    }
                case .target(let target, _):
                    if let target = target as? BinaryTarget {
                        // Add the executables vended by the binary target to the tool map.
                        for exec in try target.parseArtifactArchives(for: pluginScriptRunner.hostTriple, fileSystem: swiftTool.fileSystem) {
                            toolNamesToPaths[exec.name] = exec.executablePath
                        }
                    }
                    else {                        
                        // Build the product referenced by the tool, and add the executable to the tool map. Product dependencies are not supported within a package, so we instead find the executable that corresponds to the product. There is always one, because of autogeneration of implicit executables with the same name as the target if there isn't an explicit one.
                        try buildOperation.build(subset: .product(target.name))
                        if let builtTool = buildOperation.buildPlan?.buildProducts.first(where: { $0.product.name == target.name}) {
                            toolNamesToPaths[target.name] = builtTool.binary
                        }
                    }
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

final class PluginDelegate: PluginInvocationDelegate {
    let swiftTool: SwiftTool
    let plugin: PluginTarget
    var lineBufferedOutput: Data
    
    init(swiftTool: SwiftTool, plugin: PluginTarget) {
        self.swiftTool = swiftTool
        self.plugin = plugin
        self.lineBufferedOutput = Data()
    }

    func pluginEmittedOutput(_ data: Data) {
        lineBufferedOutput += data
        while let newlineIdx = lineBufferedOutput.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBufferedOutput.prefix(upTo: newlineIdx)
            print(String(decoding: lineData, as: UTF8.self))
            lineBufferedOutput = lineBufferedOutput.suffix(from: newlineIdx.advanced(by: 1))
        }
    }
    
    func pluginEmittedDiagnostic(_ diagnostic: Basics.Diagnostic) {
        swiftTool.observabilityScope.emit(diagnostic)
    }
    
    func pluginRequestedBuildOperation(subset: PluginInvocationBuildSubset, parameters: PluginInvocationBuildParameters, completion: @escaping (Result<PluginInvocationBuildResult, Error>) -> Void) {
        // Run the build in the background and call the completion handler when done.
        DispatchQueue.sharedConcurrent.async {
            completion(Result {
                return try self.performBuildForPlugin(subset: subset, parameters: parameters)
            })
        }
    }
    
    private func performBuildForPlugin(subset: PluginInvocationBuildSubset, parameters: PluginInvocationBuildParameters) throws -> PluginInvocationBuildResult {
        // Configure the build parameters.
        var buildParameters = try self.swiftTool.buildParameters()
        switch parameters.configuration {
        case .debug:
            buildParameters.configuration = .debug
        case .release:
            buildParameters.configuration = .release
        }
        buildParameters.flags.cCompilerFlags.append(contentsOf: parameters.otherCFlags)
        buildParameters.flags.cxxCompilerFlags.append(contentsOf: parameters.otherCxxFlags)
        buildParameters.flags.swiftCompilerFlags.append(contentsOf: parameters.otherSwiftcFlags)
        buildParameters.flags.linkerFlags.append(contentsOf: parameters.otherLinkerFlags)

        // Configure the verbosity of the output.
        let logLevel: Diagnostic.Severity
        switch parameters.logging {
        case .concise:
            logLevel = .warning
        case .verbose:
            logLevel = .info
        case .debug:
            logLevel = .debug
        }

        // Determine the subset of products and targets to build.
        var explicitProduct: String? = .none
        let buildSubset: BuildSubset
        switch subset {
        case .all(let includingTests):
            buildSubset = includingTests ? .allIncludingTests : .allExcludingTests
        case .product(let name):
            buildSubset = .product(name)
            explicitProduct = name
        case .target(let name):
            buildSubset = .target(name)
        }

        // Create a build operation. We have to disable the cache in order to get a build plan created.
        let outputStream = BufferedOutputByteStream()
        let buildOperation = BuildOperation(
            buildParameters: buildParameters,
            cacheBuildManifest: false,
            packageGraphLoader: { try self.swiftTool.loadPackageGraph(explicitProduct: explicitProduct) },
            pluginScriptRunner: try self.swiftTool.getPluginScriptRunner(),
            pluginWorkDirectory: try self.swiftTool.getActiveWorkspace().location.pluginWorkingDirectory,
            outputStream: outputStream,
            logLevel: logLevel,
            fileSystem: swiftTool.fileSystem,
            observabilityScope: self.swiftTool.observabilityScope
        )

        // Save the instance so it can be canceled from the interrupt handler.
        self.swiftTool.buildSystemRef.buildSystem = buildOperation

        // Get or create the build description and plan the build.
        let _ = try buildOperation.getBuildDescription()
        let buildPlan = buildOperation.buildPlan!
        
        // Run the build. This doesn't return until the build is complete.
        var success = true
        do {
            try buildOperation.build(subset: buildSubset)
        }
        catch {
            success = false
        }

        // Create and return the build result record based on what the delegate collected and what's in the build plan.
        let builtProducts = buildPlan.buildProducts.filter {
            switch subset {
            case .all(let includingTests):
                return includingTests ? true : $0.product.type != .test
            case .product(let name):
                return $0.product.name == name
            case .target(let name):
                return $0.product.name == name
            }
        }
        let builtArtifacts: [PluginInvocationBuildResult.BuiltArtifact] = builtProducts.compactMap {
            switch $0.product.type {
            case .library(let kind):
                return .init(path: $0.binary.pathString, kind: (kind == .dynamic) ? .dynamicLibrary : .staticLibrary)
            case .executable:
                return .init(path: $0.binary.pathString, kind: .executable)
            default:
                return nil
            }
        }
        return PluginInvocationBuildResult(
            succeeded: success,
            logText: outputStream.bytes.cString,
            builtArtifacts: builtArtifacts)
    }

    func pluginRequestedTestOperation(subset: PluginInvocationTestSubset, parameters: PluginInvocationTestParameters, completion: @escaping (Result<PluginInvocationTestResult, Error>) -> Void) {
        // Run the test in the background and call the completion handler when done.
        DispatchQueue.sharedConcurrent.async {
            completion(Result {
                return try self.performTestsForPlugin(subset: subset, parameters: parameters)
            })
        }
    }
    
    func performTestsForPlugin(subset: PluginInvocationTestSubset, parameters: PluginInvocationTestParameters) throws -> PluginInvocationTestResult {
        // Build the tests. Ideally we should only build those that match the subset, but we don't have a way to know which ones they are until we've built them and can examine the binaries.
        let toolchain = try swiftTool.getToolchain()
        var buildParameters = try swiftTool.buildParameters()
        buildParameters.enableTestability = true
        buildParameters.enableCodeCoverage = parameters.enableCodeCoverage
        let buildSystem = try swiftTool.createBuildSystem(customBuildParameters: buildParameters)
        try buildSystem.build(subset: .allIncludingTests)

        // Clean out the code coverage directory that may contain stale `profraw` files from a previous run of the code coverage tool.
        if parameters.enableCodeCoverage {
            try swiftTool.fileSystem.removeFileTree(buildParameters.codeCovPath)
        }

        // Construct the environment we'll pass down to the tests.
        var environmentOptions = swiftTool.options
        environmentOptions.shouldEnableCodeCoverage = parameters.enableCodeCoverage
        let testEnvironment = try TestingSupport.constructTestEnvironment(
            toolchain: toolchain,
            options: environmentOptions,
            buildParameters: buildParameters)

        // Iterate over the tests and run those that match the filter.
        var testTargetResults: [PluginInvocationTestResult.TestTarget] = []
        var numFailedTests = 0
        for testProduct in buildSystem.builtTestProducts {
            // Get the test suites in the bundle. Each is just a container for test cases.
            let testSuites = try TestingSupport.getTestSuites(fromTestAt: testProduct.bundlePath, swiftTool: swiftTool, swiftOptions: swiftTool.options)
            for testSuite in testSuites {
                // Each test suite is just a container for test cases (confusingly called "tests", though they are test cases).
                for testCase in testSuite.tests {
                    // Each test case corresponds to a combination of target and a XCTestCase, and is a collection of tests that can actually be run.
                    var testResults: [PluginInvocationTestResult.TestTarget.TestCase.Test] = []
                    for testName in testCase.tests {
                        // Check if we should filter out this test.
                        let testSpecifier = testCase.name + "/" + testName
                        if case .filtered(let regexes) = subset {
                            guard regexes.contains(where: { testSpecifier.range(of: $0, options: .regularExpression) != nil }) else {
                                continue
                            }
                        }

                        // Configure a test runner.
                        let testRunner = TestRunner(
                            bundlePaths: [testProduct.bundlePath],
                            xctestArg: testSpecifier,
                            processSet: swiftTool.processSet,
                            toolchain: toolchain,
                            testEnv: testEnvironment,
                            observabilityScope: swiftTool.observabilityScope)

                        // Run the test — for now we run the sequentially so we can capture accurate timing results.
                        let startTime = DispatchTime.now()
                        let success = testRunner.test(outputHandler: { _ in }) // this drops the tests output
                        let duration = Double(startTime.distance(to: .now()).milliseconds() ?? 0) / 1000.0
                        numFailedTests += success ? 0 : 1
                        testResults.append(.init(name: testName, result: success ? .succeeded : .failed, duration: duration))
                    }

                    // Don't add any results if we didn't run any tests.
                    if testResults.isEmpty { continue }

                    // Otherwise we either create a new create a new target result or add to the previous one, depending on whether the target name is the same.
                    let testTargetName = testCase.name.prefix(while: { $0 != "." })
                    if let lastTestTargetName = testTargetResults.last?.name, testTargetName == lastTestTargetName {
                        // Same as last one, just extend its list of cases. We know we have a last one at this point.
                        testTargetResults[testTargetResults.count-1].testCases.append(.init(name: testCase.name, tests: testResults))
                    }
                    else {
                        // Not the same, so start a new target result.
                        testTargetResults.append(.init(name: String(testTargetName), testCases: [.init(name: testCase.name, tests: testResults)]))
                    }
                }
            }
        }

        // Deal with code coverage, if enabled.
        let codeCoverageDataFile: AbsolutePath?
        if parameters.enableCodeCoverage {
            // Use `llvm-prof` to merge all the `.profraw` files into a single `.profdata` file.
            let mergedCovFile = buildParameters.codeCovDataFile
            let codeCovFileNames = try swiftTool.fileSystem.getDirectoryContents(buildParameters.codeCovPath)
            var llvmProfCommand = [try toolchain.getLLVMProf().pathString]
            llvmProfCommand += ["merge", "-sparse"]
            for fileName in codeCovFileNames where fileName.hasSuffix(".profraw") {
                let filePath = buildParameters.codeCovPath.appending(component: fileName)
                llvmProfCommand.append(filePath.pathString)
            }
            llvmProfCommand += ["-o", mergedCovFile.pathString]
            try Process.checkNonZeroExit(arguments: llvmProfCommand)

            // Use `llvm-cov` to export the merged `.profdata` file contents in JSON form.
            var llvmCovCommand = [try toolchain.getLLVMCov().pathString]
            llvmCovCommand += ["export", "-instr-profile=\(mergedCovFile.pathString)"]
            for product in buildSystem.builtTestProducts {
                llvmCovCommand.append("-object")
                llvmCovCommand.append(product.binaryPath.pathString)
            }
            // We get the output on stdout, and have to write it to a JSON ourselves.
            let jsonOutput = try Process.checkNonZeroExit(arguments: llvmCovCommand)
            let jsonCovFile = buildParameters.codeCovDataFile.parentDirectory.appending(component: buildParameters.codeCovDataFile.basenameWithoutExt + ".json")
            try swiftTool.fileSystem.writeFileContents(jsonCovFile, string: jsonOutput)

            // Return the path of the exported code coverage data file.
            codeCoverageDataFile = jsonCovFile
        }
        else {
            codeCoverageDataFile = nil
        }

        // Return the results to the plugin. We only consider the test run a success if no test failed.
        return PluginInvocationTestResult(
            succeeded: (numFailedTests == 0),
            testTargets: testTargetResults,
            codeCoverageDataFile: codeCoverageDataFile?.pathString)
    }

    func pluginRequestedSymbolGraph(forTarget targetName: String, options: PluginInvocationSymbolGraphOptions, completion: @escaping (Result<PluginInvocationSymbolGraphResult, Error>) -> Void) {
        // Extract the symbol graph in the background and call the completion handler when done.
        DispatchQueue.sharedConcurrent.async {
            completion(Result {
                return try self.createSymbolGraphForPlugin(forTarget: targetName, options: options)
            })
        }
    }

    private func createSymbolGraphForPlugin(forTarget targetName: String, options: PluginInvocationSymbolGraphOptions) throws -> PluginInvocationSymbolGraphResult {
        // Current implementation uses `SymbolGraphExtract()` but in the future we should emit the symbol graph while building.

        // Create a build operation for building the target., skipping the the cache because we need the build plan.
        let buildOperation = try swiftTool.createBuildOperation(cacheBuildManifest: false)

        // Find the target in the build operation's package graph; it's an error if we don't find it.
        let packageGraph = try buildOperation.getPackageGraph()
        guard let target = packageGraph.allTargets.first(where: { $0.name == targetName }) else {
            throw StringError("could not find a target named “\(targetName)”")
        }

        // Build the target, if needed.
        try buildOperation.build(subset: .target(target.name))

        // Configure the symbol graph extractor.
        var symbolGraphExtractor = try SymbolGraphExtract(
            fileSystem: swiftTool.fileSystem,
            tool: swiftTool.getToolchain().getSymbolGraphExtract()
        )
        symbolGraphExtractor.skipSynthesizedMembers = !options.includeSynthesized
        switch options.minimumAccessLevel {
        case .private:
            symbolGraphExtractor.minimumAccessLevel = .private
        case .fileprivate:
            symbolGraphExtractor.minimumAccessLevel = .fileprivate
        case .internal:
            symbolGraphExtractor.minimumAccessLevel = .internal
        case .public:
            symbolGraphExtractor.minimumAccessLevel = .public
        case .open:
            symbolGraphExtractor.minimumAccessLevel = .open
        }
        symbolGraphExtractor.skipInheritedDocs = true
        symbolGraphExtractor.includeSPISymbols = options.includeSPI

        // Determine the output directory, and remove any old version if it already exists.
        guard let buildPlan = buildOperation.buildPlan else {
            throw StringError("could not get the build plan from the build operation")
        }
        guard let package = packageGraph.package(for: target) else {
            throw StringError("could not determine the package for target “\(target.name)”")
        }
        let outputDir = buildPlan.buildParameters.dataPath.appending(components: "extracted-symbols", package.identity.description, target.name)
        try swiftTool.fileSystem.removeFileTree(outputDir)

        // Run the symbol graph extractor on the target.
        try symbolGraphExtractor.extractSymbolGraph(
            target: target,
            buildPlan: buildPlan,
            outputRedirection: .collect,
            outputDirectory: outputDir,
            verboseOutput: self.swiftTool.logLevel <= .info
        )

        // Return the results to the plugin.
        return PluginInvocationSymbolGraphResult(directoryPath: outputDir.pathString)
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
            commandName: "",
            shouldDisplay: false)

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

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
                options: pluginOptions,
                arguments: Array( remaining.dropFirst()),
                swiftTool: swiftTool)
        }
    }
}

extension SwiftPackageTool {
    struct GenerateXcodeProject: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate-xcodeproj",
            abstract: "Generates an Xcode project. This command will be deprecated soon.")

        struct Options: ParsableArguments {
            @Option(help: "Path to xcconfig file", completion: .file())
            var xcconfigOverrides: AbsolutePath?

            @Option(name: .customLong("output"),
                    help: "Path where the Xcode project should be generated")
            var outputPath: AbsolutePath?

            @Flag(name: .customLong("legacy-scheme-generator"),
                  help: "Use the legacy scheme generator")
            var useLegacySchemeGenerator: Bool = false

            @Flag(name: .customLong("watch"),
                  help: "Watch for changes to the Package manifest to regenerate the Xcode project")
            var enableAutogeneration: Bool = false

            @Flag(help: "Do not add file references for extra files to the generated Xcode project")
            var skipExtraFiles: Bool = false
        }

        @OptionGroup(_hiddenFromHelp: true)
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var options: Options

        func xcodeprojOptions() -> XcodeprojOptions {
            XcodeprojOptions(
                flags: swiftOptions.buildFlags,
                xcconfigOverrides: options.xcconfigOverrides,
                isCodeCoverageEnabled: swiftOptions.shouldEnableCodeCoverage,
                useLegacySchemeGenerator: options.useLegacySchemeGenerator,
                enableAutogeneration: options.enableAutogeneration,
                addExtraFiles: !options.skipExtraFiles)
        }

        func run(_ swiftTool: SwiftTool) throws {
            swiftTool.observabilityScope.emit(warning: "Xcode can open and build Swift Packages directly. 'generate-xcodeproj' is no longer needed and will be deprecated soon.")

            let graph = try swiftTool.loadPackageGraph()

            let projectName: String
            let dstdir: AbsolutePath

            switch options.outputPath {
            case let outpath? where outpath.suffix == ".xcodeproj":
                // if user specified path ending with .xcodeproj, use that
                projectName = String(outpath.basename.dropLast(10))
                dstdir = outpath.parentDirectory
            case let outpath?:
                dstdir = outpath
                projectName = graph.rootPackages[0].manifest.displayName // TODO: use identity instead?
            case _:
                dstdir = try swiftTool.getPackageRoot()
                projectName = graph.rootPackages[0].manifest.displayName // TODO: use identity instead?
            }
            let xcodeprojPath = XcodeProject.makePath(outputDir: dstdir, projectName: projectName)

            var genOptions = xcodeprojOptions()
            genOptions.manifestLoader = try swiftTool.getManifestLoader()

            try XcodeProject.generate(
                projectName: projectName,
                xcodeprojPath: xcodeprojPath,
                graph: graph,
                options: genOptions,
                fileSystem: swiftTool.fileSystem,
                observabilityScope: swiftTool.observabilityScope
            )

            print("generated:", xcodeprojPath.prettyPath(cwd: swiftTool.originalWorkingDirectory))

            // Run the file watcher if requested.
            if options.enableAutogeneration {
                try WatchmanHelper(
                    watchmanScriptsDir: swiftTool.buildPath.appending(component: "watchman"),
                    packageRoot: swiftTool.packageRoot!,
                    fileSystem: swiftTool.fileSystem,
                    observabilityScope: swiftTool.observabilityScope
                ).runXcodeprojWatcher(xcodeprojOptions())
            }
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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

        @OptionGroup()
        var resolveOptions: ResolveOptions

        func run(_ swiftTool: SwiftTool) throws {
            swiftTool.observabilityScope.emit(warning: "'fetch' command is deprecated; use 'resolve' instead")

            let resolveCommand = Resolve(swiftOptions: _swiftOptions, resolveOptions: _resolveOptions)
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
        var swiftOptions: SwiftToolOptions

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
        var swiftOptions: SwiftToolOptions

        static let configuration = CommandConfiguration(abstract: "Learn about Swift and this package")

        func files(fileSystem: FileSystem, in directory: AbsolutePath, fileExtension: String? = nil) throws -> [AbsolutePath] {
            guard fileSystem.isDirectory(directory) else {
                return []
            }

            let files = try fileSystem.getDirectoryContents(directory)
                .map { directory.appending(RelativePath($0)) }
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
                .map { directory.appending(RelativePath($0)) }
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
