/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import TSCBasic
import SPMBuildCore
import Build
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import TSCUtility
import Xcodeproj
import XCBuildSupport
import Workspace
import Foundation

/// swift-package tool namespace
public struct SwiftPackageTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package",
        _superCommandName: "swift",
        abstract: "Perform operations on Swift packages",
        discussion: "SEE ALSO: swift build, swift run, swift test",
        version: Versioning.currentVersion.completeDisplayString,
        subcommands: [
            Clean.self,
            Reset.self,
            Update.self,
            Describe.self,
            Init.self,
            Format.self,
            
            APIDiff.self,
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
            CompletionTool.self,
        ],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])

    @OptionGroup()
    var swiftOptions: SwiftToolOptions

    public init() {}

    public static var _errorLabel: String { "error" }
}

extension DescribeMode: ExpressibleByArgument {}
extension InitPackage.PackageType: ExpressibleByArgument {}
extension ShowDependenciesMode: ExpressibleByArgument {}

extension SwiftPackageTool {
    struct Clean: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete build artifacts")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().clean(with: swiftTool.diagnostics)
        }
    }
    
    struct Reset: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reset the complete cache/build directory")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        func run(_ swiftTool: SwiftTool) throws {
            try swiftTool.getActiveWorkspace().reset(with: swiftTool.diagnostics)
        }
    }
    
    struct Update: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update package dependencies")

        @OptionGroup()
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
                diagnostics: swiftTool.diagnostics,
                dryRun: dryRun
            )
            
            if let pinsStore = swiftTool.diagnostics.wrap({ try workspace.pinsStore.load() }),
                let changes = changes,
                dryRun {
                logPackageChanges(changes: changes, pins: pinsStore)
            }
        }
    }
    
    struct Describe: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Describe the current package")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
                
        @Option()
        var type: DescribeMode = .text

        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            let root = try swiftTool.getWorkspaceRoot()
            
            let manifests = workspace.loadRootManifests(
                packages: root.packages, diagnostics: swiftTool.diagnostics)
            guard let manifest = manifests.first else { return }

            let builder = PackageBuilder(
                manifest: manifest,
                productFilter: .everything,
                path: try swiftTool.getPackageRoot(),
                xcTestMinimumDeploymentTargets: MinimumDeploymentTarget.default.xcTestMinimumDeploymentTargets,
                diagnostics: swiftTool.diagnostics
            )
            let package = try builder.construct()
            describe(package, in: type, on: stdoutStream)
        }
    }

    struct Init: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Initialize a new package")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option(name: .customLong("type"))
        var initMode: InitPackage.PackageType = .library
        
        @Option(name: .customLong("name"), help: "Provide custom package name")
        var packageName: String?

        func run(_ swiftTool: SwiftTool) throws {
            // FIXME: Error handling.
            let cwd = localFileSystem.currentWorkingDirectory!

            let packageName = self.packageName ?? cwd.basename
            let initPackage = try InitPackage(
                name: packageName, destinationPath: cwd, packageType: initMode)
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()
        }
    }
    
    struct Format: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "_format")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Argument(parsing: .unconditionalRemaining,
                  help: "Pass flag through to the swift-format tool")
        var swiftFormatFlags: [String] = []
        
        func run(_ swiftTool: SwiftTool) throws {
            // Look for swift-format binary.
            // FIXME: This should be moved to user toolchain.
            let swiftFormatInEnv = lookupExecutablePath(filename: ProcessEnv.vars["SWIFT_FORMAT"])
            guard let swiftFormat = swiftFormatInEnv ?? Process.findExecutable("swift-format") else {
                print("error: Could not find swift-format in PATH or SWIFT_FORMAT")
                throw Diagnostics.fatalError
            }

            // Get the root package.
            let workspace = try swiftTool.getActiveWorkspace()
            let root = try swiftTool.getWorkspaceRoot()
            let manifest = workspace.loadRootManifests(
                packages: root.packages, diagnostics: swiftTool.diagnostics)[0]

            let builder = PackageBuilder(
                manifest: manifest,
                productFilter: .everything,
                path: try swiftTool.getPackageRoot(),
                xcTestMinimumDeploymentTargets: [:], // Minimum deployment target does not matter for this operation.
                diagnostics: swiftTool.diagnostics
            )
            let package = try builder.construct()

            // Use the user provided flags or default to formatting mode.
            let formatOptions = swiftFormatFlags.isEmpty
                ? ["--mode", "format", "--in-place"]
                : swiftFormatFlags

            // Process each target in the root package.
            for target in package.targets {
                for file in target.sources.paths {
                    // Only process Swift sources.
                    guard let ext = file.extension, ext == SupportedLanguageExtension.swift.rawValue else {
                        continue
                    }

                    let args = [swiftFormat.pathString] + formatOptions + [file.pathString]
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
        }
    }
    
    struct APIDiff: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "experimental-api-diff")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions

        @Argument(help: "The baseline treeish")
        var treeish: String
        
        @Flag(help: "Invert the baseline which is helpful for determining API additions")
        var invertBaseline: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let apiDigesterPath = try swiftTool.getToolchain().getSwiftAPIDigester()
            let apiDigesterTool = SwiftAPIDigester(tool: apiDigesterPath)

            // Build the current package.
            //
            // We turn build manifest caching off because we need the build plan.
            let buildOp = try swiftTool.createBuildOperation(useBuildManifestCaching: false)
            try buildOp.build()

            // Dump JSON for the current package.
            let buildParameters = buildOp.buildParameters
            let currentSDKJSON = buildParameters.apiDiff.appending(component: "current.json")
            let packageGraph = try buildOp.getPackageGraph()

            try apiDigesterTool.dumpSDKJSON(
                at: currentSDKJSON,
                modules: packageGraph.apiDigesterModules,
                additionalArgs: buildOp.buildPlan!.createAPIDigesterArgs()
            )

            // Dump JSON for the baseline package.
            let workspace = try swiftTool.getActiveWorkspace()
            let baselineDumper = try APIDigesterBaselineDumper(
                baselineTreeish: treeish,
                packageRoot: swiftTool.getPackageRoot(),
                buildParameters: buildParameters,
                manifestLoader: workspace.manifestLoader,
                repositoryManager: workspace.repositoryManager,
                apiDigesterTool: apiDigesterTool,
                diags: swiftTool.diagnostics
            )
            let baselineSDKJSON = try baselineDumper.dumpBaselineSDKJSON()

            // Run the diagnose tool which will print the diff.
            try apiDigesterTool.diagnoseSDK(
                currentSDKJSON: invertBaseline ? baselineSDKJSON : currentSDKJSON,
                baselineSDKJSON: invertBaseline ? currentSDKJSON : baselineSDKJSON
            )
        }
    }
    
    struct DumpSymbolGraph: SwiftCommand {
        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        func run(_ swiftTool: SwiftTool) throws {
            let symbolGraphExtract = try SymbolGraphExtract(
                tool: swiftTool.getToolchain().getSymbolGraphExtract())

            // Build the current package.
            //
            // We turn build manifest caching off because we need the build plan.
            let buildOp = try swiftTool.createBuildOperation(useBuildManifestCaching: false)
            try buildOp.build()

            try symbolGraphExtract.dumpSymbolGraph(
                buildPlan: buildOp.buildPlan!
            )
        }
    }
    
    struct DumpPackage: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print parsed Package.swift as JSON")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            let root = try swiftTool.getWorkspaceRoot()
            
            let manifests = workspace.loadRootManifests(
                packages: root.packages, diagnostics: swiftTool.diagnostics)
            guard let manifest = manifests.first else { return }

            let encoder = JSONEncoder()
            encoder.userInfo[Manifest.dumpPackageKey] = true
            if #available(macOS 10.13, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            }

            let jsonData = try encoder.encode(manifest)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print(jsonString)
        }
    }
    
    struct DumpPIF: SwiftCommand {
        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Flag(help: "Preserve the internal structure of PIF")
        var preserveStructure: Bool = false

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph(createMultipleTestProducts: true)
            let parameters = try PIFBuilderParameters(swiftTool.buildParameters())
            let builder = PIFBuilder(graph: graph, parameters: parameters, diagnostics: swiftTool.diagnostics)
            let pif = try builder.generatePIF(preservePIFModelStructure: preserveStructure)
            print(pif)
        }
    }
    
    struct Edit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Put a package in editable mode")

        @OptionGroup()
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
                diagnostics: swiftTool.diagnostics)
        }
    }

    struct Unedit: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a package from editable mode")

        @OptionGroup()
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
                diagnostics: swiftTool.diagnostics
            )
        }
    }
    
    struct ShowDependencies: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print the resolved dependency graph")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option()
        var format: ShowDependenciesMode = .text

        func run(_ swiftTool: SwiftTool) throws {
            let graph = try swiftTool.loadPackageGraph()
            dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: format)
        }
    }
    
    struct ToolsVersionCommand: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "tools-version",
            abstract: "Manipulate tools version of the current package")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option()
        var format: ShowDependenciesMode = .text

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
                let version = try toolsVersionLoader.load(at: pkg, fileSystem: localFileSystem)
                print("\(version)")

            case .set(let value):
                guard let toolsVersion = ToolsVersion(string: value) else {
                    // FIXME: Probably lift this error defination to ToolsVersion.
                    throw ToolsVersionLoader.Error.malformed(specifier: value, currentToolsVersion: .currentToolsVersion)
                }
                try writeToolsVersion(at: pkg, version: toolsVersion, fs: localFileSystem)

            case .setCurrent:
                // Write the tools version with current version but with patch set to zero.
                // We do this to avoid adding unnecessary constraints to patch versions, if
                // the package really needs it, they can do it using --set option.
                try writeToolsVersion(
                    at: pkg, version: ToolsVersion.currentToolsVersion.zeroedPatch, fs: localFileSystem)
            }
        }
    }
    
    struct ComputeChecksum: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compute the checksum for a binary artifact.")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Argument(help: "The absolute or relative path to the binary artifact")
        var path: AbsolutePath
        
        func run(_ swiftTool: SwiftTool) throws {
            let workspace = try swiftTool.getActiveWorkspace()
            let checksum = workspace.checksum(
                forBinaryArtifactAt: path,
                diagnostics: swiftTool.diagnostics
            )

            guard !swiftTool.diagnostics.hasErrors else {
                throw ExitCode.failure
            }

            stdoutStream <<< checksum <<< "\n"
            stdoutStream.flush()
        }
    }
}

extension SwiftPackageTool {
    struct GenerateXcodeProject: SwiftCommand {
        static let configuration = CommandConfiguration(
            commandName: "generate-xcodeproj",
            abstract: "Generates an Xcode project")

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

        @OptionGroup()
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
                projectName = graph.rootPackages[0].name
            case _:
                dstdir = try swiftTool.getPackageRoot()
                projectName = graph.rootPackages[0].name
            }
            let xcodeprojPath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)

            var genOptions = xcodeprojOptions()
            genOptions.manifestLoader = try swiftTool.getManifestLoader()

            try Xcodeproj.generate(
                projectName: projectName,
                xcodeprojPath: xcodeprojPath,
                graph: graph,
                options: genOptions,
                diagnostics: swiftTool.diagnostics
            )

            print("generated:", xcodeprojPath.prettyPath(cwd: swiftTool.originalWorkingDirectory))

            // Run the file watcher if requested.
            if options.enableAutogeneration {
                try WatchmanHelper(
                    diagnostics: swiftTool.diagnostics,
                    watchmanScriptsDir: swiftTool.buildPath.appending(component: "watchman"),
                    packageRoot: swiftTool.packageRoot!
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

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option(help: "The package dependency url")
        var packageURL: String?
        
        @Option(help: "The original url")
        var originalURL: String?
        
        @Option(help: "The mirror url")
        var mirrorURL: String
        
        func run(_ swiftTool: SwiftTool) throws {
            let config = try swiftTool.getSwiftPMConfig()
            try config.load()

            if packageURL != nil {
                swiftTool.diagnostics.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = packageURL ?? originalURL else {
                swiftTool.diagnostics.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            try config.set(mirrorURL: mirrorURL, forURL: originalURL)
        }
    }

    struct UnsetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove an existing mirror")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option(help: "The package dependency url")
        var packageURL: String?
        
        @Option(help: "The original url")
        var originalURL: String?
        
        @Option(help: "The mirror url")
        var mirrorURL: String?
        
        func run(_ swiftTool: SwiftTool) throws {
            let config = try swiftTool.getSwiftPMConfig()
            try config.load()

            if packageURL != nil {
                swiftTool.diagnostics.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalOrMirrorURL = packageURL ?? originalURL ?? mirrorURL else {
                swiftTool.diagnostics.emit(.missingRequiredArg("--original-url or --mirror-url"))
                throw ExitCode.failure
            }

            try config.unset(originalOrMirrorURL: originalOrMirrorURL)
        }
    }

    struct GetMirror: SwiftCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print mirror configuration for the given package dependency")

        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @Option(help: "The package dependency url")
        var packageURL: String?
        
        @Option(help: "The original url")
        var originalURL: String?

        func run(_ swiftTool: SwiftTool) throws {
            let config = try swiftTool.getSwiftPMConfig()
            try config.load()

            if packageURL != nil {
                swiftTool.diagnostics.emit(
                    warning: "'--package-url' option is deprecated; use '--original-url' instead")
            }

            guard let originalURL = packageURL ?? originalURL else {
                swiftTool.diagnostics.emit(.missingRequiredArg("--original-url"))
                throw ExitCode.failure
            }

            if let mirror = config.getMirror(forURL: originalURL) {
                print(mirror)
            } else {
                stderrStream <<< "not found\n"
                stderrStream.flush()
                throw ExitCode.failure
            }
        }
    }
}

extension SwiftPackageTool {
    struct ResolveOptions: ParsableArguments {
        @Option(help: "The version to resolve at", transform: { Version(string: $0) })
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
        
        @OptionGroup()
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
                    diagnostics: swiftTool.diagnostics)
                if swiftTool.diagnostics.hasErrors {
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
        
        @OptionGroup()
        var swiftOptions: SwiftToolOptions
        
        @OptionGroup()
        var resolveOptions: ResolveOptions
        
        func run(_ swiftTool: SwiftTool) throws {
            swiftTool.diagnostics.emit(warning: "'fetch' command is deprecated; use 'resolve' instead")
            
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
      
        @OptionGroup()
        var swiftOptions: SwiftToolOptions

        @Argument()
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
                dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: .flatlist)
            case .listExecutables:
                let graph = try swiftTool.loadPackageGraph()
                let package = graph.rootPackages[0].underlyingPackage
                let executables = package.targets.filter { $0.type == .executable }
                for executable in executables {
                    stdoutStream <<< "\(executable.name)\n"
                }
                stdoutStream.flush()
            }
        }
    }
}

private extension Diagnostic.Message {
    static var missingRequiredSubcommand: Diagnostic.Message {
        .error("missing required subcommand; use --help to list available subcommands")
    }

    static func missingRequiredArg(_ argument: String) -> Diagnostic.Message {
        .error("missing required argument \(argument)")
    }
}

/// Logs all changed dependencies to a stream
/// - Parameter changes: Changes to log
/// - Parameter pins: PinsStore with currently pinned packages to compare changed packages to.
/// - Parameter stream: Stream used for logging
fileprivate func logPackageChanges(changes: [(PackageReference, Workspace.PackageStateChange)], pins: PinsStore, on stream: OutputByteStream = TSCBasic.stdoutStream) {
    let changes = changes.filter { $0.1 != .unchanged }
    
    stream <<< "\n"
    stream <<< "\(changes.count) dependenc\(changes.count == 1 ? "y has" : "ies have") changed\(changes.count > 0 ? ":" : ".")"
    stream <<< "\n"
    
    for (package, change) in changes {
        let currentVersion = pins.pinsMap[package.identity]?.state.description ?? ""
        switch change {
        case let .added(state):
            stream <<< "+ \(package.name) \(state.requirement.prettyPrinted)"
        case let .updated(state):
            stream <<< "~ \(package.name) \(currentVersion) -> \(package.name) \(state.requirement.prettyPrinted)"
        case .removed:
            stream <<< "- \(package.name) \(currentVersion)"
        case .unchanged:
            continue
        }
        stream <<< "\n"
    }
    stream.flush()
}
