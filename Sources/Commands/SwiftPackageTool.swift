/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import Build
import PackageModel
import PackageLoading
import PackageGraph
import SourceControl
import Utility
import Xcodeproj
import Workspace
import Foundation

struct FetchDeprecatedDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: AnyDiagnostic.self,
        name: "org.swift.diags.fetch-deprecated",
        defaultBehavior: .warning,
        description: {
            $0 <<< "'fetch' command is deprecated; use 'resolve' instead"
        }
    )
}

/// swift-package tool namespace
public class SwiftPackageTool: SwiftTool<PackageToolOptions> {

   public convenience init(args: [String]) {
       self.init(
            toolName: "package",
            usage: "[options] subcommand",
            overview: "Perform operations on Swift packages",
            args: args,
            seeAlso: type(of: self).otherToolNames()
        )
    }
    
    override func runImpl() throws {
        switch options.mode {
        case .version:
            print(Versioning.currentVersion.completeDisplayString)

        case .initPackage:
            // FIXME: Error handling.
            let cwd = localFileSystem.currentWorkingDirectory!
            
            let packageName = options.packageName ?? cwd.basename
            let initPackage = try InitPackage(
                name: packageName, destinationPath: cwd, packageType: options.initMode)
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()

        case .clean:
            try getActiveWorkspace().clean(with: diagnostics)

        case .reset:
            try getActiveWorkspace().reset(with: diagnostics)

        case .update:
            let workspace = try getActiveWorkspace()
            try workspace.updateDependencies(
                root: getWorkspaceRoot(),
                diagnostics: diagnostics
            )

        case .fetch:
            diagnostics.emit(data: FetchDeprecatedDiagnostic())
            try resolve()

        case .resolve:
            let resolveOptions = options.resolveOptions

            // If a package is provided, use that to resolve the dependencies.
            if let packageName = resolveOptions.packageName {
                let workspace = try getActiveWorkspace()
                return try workspace.resolve(
                    packageName: packageName,
                    root: getWorkspaceRoot(),
                    version: resolveOptions.version.flatMap(Version.init(string:)),
                    branch: resolveOptions.branch,
                    revision: resolveOptions.revision,
                    diagnostics: diagnostics)
            }

            // Otherwise, run a normal resolve.
            try resolve()

        case .edit:
            let packageName = options.editOptions.packageName!
            try resolve()
            let workspace = try getActiveWorkspace()

            // Create revision object if provided by user.
            let revision = options.editOptions.revision.flatMap({ Revision(identifier: $0) })

            // Put the dependency in edit mode.
            workspace.edit(
                packageName: packageName,
                path: options.editOptions.path,
                revision: revision,
                checkoutBranch: options.editOptions.checkoutBranch,
                diagnostics: diagnostics)

        case .unedit:
            let packageName = options.editOptions.packageName!
            try resolve()
            let workspace = try getActiveWorkspace()

            try workspace.unedit(
                packageName: packageName,
                forceRemove: options.editOptions.shouldForceRemove,
                root: getWorkspaceRoot(),
                diagnostics: diagnostics
            )

        case .showDependencies:
            let graph = try loadPackageGraph()
            dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: options.showDepsMode)

        case .toolsVersion:
            let pkg = try getPackageRoot()

            switch options.toolsVersionMode {
            case .display:
                let toolsVersionLoader = ToolsVersionLoader()
                let version = try toolsVersionLoader.load(at: pkg, fileSystem: localFileSystem)
                print("\(version)")

            case .set(let value):
                guard let toolsVersion = ToolsVersion(string: value) else {
                    // FIXME: Probably lift this error defination to ToolsVersion.
                    throw ToolsVersionLoader.Error.malformed(specifier: value, file: pkg)
                }
                try writeToolsVersion(at: pkg, version: toolsVersion, fs: &localFileSystem)

            case .setCurrent:
                // Write the tools version with current version but with patch set to zero.
                // We do this to avoid adding unnecessary constraints to patch versions, if
                // the package really needs it, they can do it using --set option.
                try writeToolsVersion(
                    at: pkg, version: ToolsVersion.currentToolsVersion.zeroedPatch, fs: &localFileSystem)
            }

        case .generateXcodeproj:
            let graph = try loadPackageGraph()

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
                dstdir = try getPackageRoot()
                projectName = graph.rootPackages[0].name
            }
            let xcodeprojPath = Xcodeproj.buildXcodeprojPath(outputDir: dstdir, projectName: projectName)

            var genOptions = options.xcodeprojOptions
            genOptions.manifestLoader = try getManifestLoader()

            try Xcodeproj.generate(
                projectName: projectName,
                xcodeprojPath: xcodeprojPath,
                graph: graph,
                options: genOptions,
                diagnostics: diagnostics
            )

            print("generated:", xcodeprojPath.prettyPath(cwd: originalWorkingDirectory))

            // Run the file watcher if requested.
            if options.xcodeprojOptions.enableAutogeneration {
                try WatchmanHelper(
                    diagnostics: diagnostics,
                    watchmanScriptsDir: buildPath.appending(component: "watchman"),
                    packageRoot: packageRoot!
                ).runXcodeprojWatcher(options.xcodeprojOptions)
            }

        case .describe:
            let workspace = try getActiveWorkspace()
            let root = try getWorkspaceRoot()
            let manifest = workspace.loadRootManifests(
                packages: root.packages, diagnostics: diagnostics)[0]

            let builder = PackageBuilder(
                manifest: manifest,
                path: try getPackageRoot(),
                diagnostics: diagnostics,
                isRootPackage: true
            )
            let package = try builder.construct()
            describe(package, in: options.describeMode, on: stdoutStream)

        case .dumpPackage:
            let workspace = try getActiveWorkspace()
            let root = try getWorkspaceRoot()
            let manifest = workspace.loadRootManifests(
                packages: root.packages, diagnostics: diagnostics)[0]

            let encoder = JSONEncoder()
            encoder.userInfo[Manifest.dumpPackageKey] = true
          #if os(macOS)
            if #available(OSX 10.13, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            }
          #else
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          #endif

            let jsonData = try encoder.encode(manifest)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print(jsonString)

        case .completionTool:
            switch options.completionToolMode {
            case .generateBashScript?:
                bash_template(on: stdoutStream)
            case .generateZshScript?:
                zsh_template(on: stdoutStream)
            case .listDependencies?:
                let graph = try loadPackageGraph()
                dumpDependenciesOf(rootPackage: graph.rootPackages[0], mode: .flatlist)
            case .listExecutables?:
                let graph = try loadPackageGraph()
                let package = graph.rootPackages[0].underlyingPackage
                let executables = package.targets.filter { $0.type == .executable }
                for executable in executables {
                    stdoutStream <<< "\(executable.name)\n"
                }
                stdoutStream.flush()
            default:
                preconditionFailure("somehow we ended up with an invalid positional argument")
            }
        case .help:
            parser.printUsage(on: stdoutStream)
        }
    }

    override class func defineArguments(parser: ArgumentParser, binder: ArgumentBinder<PackageToolOptions>) {
        let describeParser = parser.add(
            subparser: PackageMode.describe.rawValue,
            overview: "Describe the current package")
        binder.bind(
            option: describeParser.add(option: "--type", kind: DescribeMode.self, usage: "json|text"),
            to: { $0.describeMode = $1 })

        _ = parser.add(subparser: PackageMode.dumpPackage.rawValue, overview: "Print parsed Package.swift as JSON")

        let editParser = parser.add(subparser: PackageMode.edit.rawValue, overview: "Put a package in editable mode")
        binder.bind(
            positional: editParser.add(
                positional: "name", kind: String.self,
                usage: "The name of the package to edit",
                completion: .function("_swift_dependency")),
            to: { $0.editOptions.packageName = $1 })
        binder.bind(
            editParser.add(
                option: "--revision", kind: String.self,
                usage: "The revision to edit"),
            editParser.add(
                option: "--branch", kind: String.self,
                usage: "The branch to create"),
            to: {
                $0.editOptions.revision = $1
                $0.editOptions.checkoutBranch = $2})

        binder.bind(
            option: editParser.add(
                option: "--path", kind: PathArgument.self,
                usage: "Create or use the checkout at this path"),
            to: { $0.editOptions.path = $1.path })

        parser.add(subparser: PackageMode.clean.rawValue, overview: "Delete build artifacts")
        parser.add(subparser: PackageMode.fetch.rawValue, overview: "")
        parser.add(subparser: PackageMode.reset.rawValue, overview: "Reset the complete cache/build directory")
        parser.add(subparser: PackageMode.update.rawValue, overview: "Update package dependencies")

        let initPackageParser = parser.add(
            subparser: PackageMode.initPackage.rawValue,
            overview: "Initialize a new package")
        binder.bind(
            option: initPackageParser.add(
                option: "--type", kind: InitPackage.PackageType.self,
                usage: "empty|library|executable|system-module"),
            to: { $0.initMode = $1 })
        
        binder.bind(
            option: initPackageParser.add(
                option: "--name", kind: String.self,
                usage: "Provide custom package name"),
            to: { $0.packageName = $1 })

        let uneditParser = parser.add(
            subparser: PackageMode.unedit.rawValue,
            overview: "Remove a package from editable mode")
        binder.bind(
            positional: uneditParser.add(
                positional: "name", kind: String.self,
                usage: "The name of the package to unedit",
                completion: .function("_swift_dependency")),
            to: { $0.editOptions.packageName = $1 })
        binder.bind(
            option: uneditParser.add(
                option: "--force", kind: Bool.self,
                usage: "Unedit the package even if it has uncommited and unpushed changes."),
            to: { $0.editOptions.shouldForceRemove = $1 })

        let showDependenciesParser = parser.add(
            subparser: PackageMode.showDependencies.rawValue,
            overview: "Print the resolved dependency graph")
        binder.bind(
            option: showDependenciesParser.add(
                option: "--format", kind: ShowDependenciesMode.self,
                usage: "text|dot|json|flatlist"),
            to: {
                $0.showDepsMode = $1})

        let toolsVersionParser = parser.add(
            subparser: PackageMode.toolsVersion.rawValue,
            overview: "Manipulate tools version of the current package")
        binder.bind(
            option: toolsVersionParser.add(
                option: "--set", kind: String.self,
                usage: "Set tools version of package to the given value"),
            to: { $0.toolsVersionMode = .set($1) })

        binder.bind(
            option: toolsVersionParser.add(
                option: "--set-current", kind: Bool.self,
                usage: "Set tools version of package to the current tools version in use"),
            to: { if $1 { $0.toolsVersionMode = .setCurrent } })

        let generateXcodeParser = parser.add(
            subparser: PackageMode.generateXcodeproj.rawValue,
            overview: "Generates an Xcode project")
        binder.bind(
            generateXcodeParser.add(
                option: "--xcconfig-overrides", kind: PathArgument.self,
                usage: "Path to xcconfig file"),
            generateXcodeParser.add(
                option: "--enable-code-coverage", kind: Bool.self,
                usage: "Enable code coverage in the generated project"),
            generateXcodeParser.add(
                option: "--output", kind: PathArgument.self,
                usage: "Path where the Xcode project should be generated"),
            to: {
                $0.xcodeprojOptions.flags = $0.buildFlags
                $0.xcodeprojOptions.xcconfigOverrides = $1?.path
                if let val = $2 { $0.xcodeprojOptions.isCodeCoverageEnabled = val }
                $0.outputPath = $3?.path
            })
        binder.bind(
            generateXcodeParser.add(
                option: "--legacy-scheme-generator", kind: Bool.self,
                usage: "Use the legacy scheme generator"),
            generateXcodeParser.add(
                option: "--watch", kind: Bool.self,
                usage: "Watch for changes to the Package manifest to regenerate the Xcode project"),
            generateXcodeParser.add(
                option: "--skip-extra-files", kind: Bool.self,
                usage: "Do not add file references for extra files to the generated Xcode project"),
            to: {
                $0.xcodeprojOptions.useLegacySchemeGenerator = $1 ?? false
                $0.xcodeprojOptions.enableAutogeneration = $2 ?? false
                $0.xcodeprojOptions.addExtraFiles = !($3 ?? false)
            })

        let completionToolParser = parser.add(
            subparser: PackageMode.completionTool.rawValue,
            overview: "Completion tool (for shell completions)")
        binder.bind(
            positional: completionToolParser.add(
                positional: "mode",
                kind: PackageToolOptions.CompletionToolMode.self,
                usage: PackageToolOptions.CompletionToolMode.usageText()),
            to: { $0.completionToolMode = $1 })

        let resolveParser = parser.add(
            subparser: PackageMode.resolve.rawValue,
            overview: "Resolve package dependencies")
        binder.bind(
            positional: resolveParser.add(
                positional: "name", kind: String.self, optional: true,
                usage: "The name of the package to resolve",
                completion: .function("_swift_dependency")),
            to: { $0.resolveOptions.packageName = $1 })

        binder.bind(
            resolveParser.add(
                option: "--version", kind: String.self,
                usage: "The version to resolve at"),
            resolveParser.add(
                option: "--branch", kind: String.self,
                usage: "The branch to resolve at"),
            resolveParser.add(
                option: "--revision", kind: String.self,
                usage: "The revision to resolve at"),
            to: {
                $0.resolveOptions.version = $1
                $0.resolveOptions.branch = $2
                $0.resolveOptions.revision = $3 })

        binder.bind(
            parser: parser,
            to: { $0.mode = PackageMode(rawValue: $1)! })
    }
}

public class PackageToolOptions: ToolOptions {
    private var _mode: PackageMode = .help
    var mode: PackageMode {
        get {
            return shouldPrintVersion ? .version : _mode
        }
        set {
            _mode = newValue
        }
    }

    var describeMode: DescribeMode = .text

    var initMode: InitPackage.PackageType = .library
    
    var packageName: String?

    var inputPath: AbsolutePath?
    var showDepsMode: ShowDependenciesMode = .text

    struct EditOptions {
        var packageName: String?
        var revision: String?
        var checkoutBranch: String?
        var path: AbsolutePath?
        var shouldForceRemove = false
    }

    var editOptions = EditOptions()

    var outputPath: AbsolutePath?
    var xcodeprojOptions = XcodeprojOptions()

    enum CompletionToolMode: String, CaseIterable {
        case generateBashScript = "generate-bash-script"
        case generateZshScript = "generate-zsh-script"
        case listDependencies = "list-dependencies"
        case listExecutables = "list-executables"

        static func usageText() -> String {
            return self.allCases.map({ $0.rawValue }).joined(separator: " | ")
        }
    }
    var completionToolMode: CompletionToolMode?

    struct ResolveOptions {
        var packageName: String?
        var version: String?
        var revision: String?
        var branch: String?
    }
    var resolveOptions = ResolveOptions()

    enum ToolsVersionMode {
        case display
        case set(String)
        case setCurrent
    }
    var toolsVersionMode: ToolsVersionMode = .display
}

public enum PackageMode: String, StringEnumArgument {
    case clean
    case describe
    case dumpPackage = "dump-package"
    case edit
    case fetch
    case generateXcodeproj = "generate-xcodeproj"
    case completionTool = "completion-tool"
    case initPackage = "init"
    case reset
    case resolve
    case showDependencies = "show-dependencies"
    case toolsVersion = "tools-version"
    case unedit
    case update
    case version
    case help

    // PackageMode is not used as an argument; completions will be
    // provided by the subparsers.
    public static var completion: ShellCompletion = .none
}

extension InitPackage.PackageType: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (empty.description, "generates an empty project"),
            (library.description, "generates project for a dynamic library"),
            (executable.description, "generates a project for a cli executable"),
            (systemModule.description, "generates a project for a system module"),
        ])
    }
}

extension ShowDependenciesMode: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (text.description, "list dependencies using text format"),
            (dot.description, "list dependencies using dot format"),
            (json.description, "list dependencies using JSON format"),
        ])
    }
}

extension DescribeMode: StringEnumArgument {
    public static var completion: ShellCompletion {
        return .values([
            (text.rawValue, "describe using text format"),
            (json.rawValue, "describe using JSON format"),
        ])
    }
}

extension PackageToolOptions.CompletionToolMode: StringEnumArgument {
    static var completion: ShellCompletion {
        return .values([
            (generateBashScript.rawValue, "generate Bash completion script"),
            (generateZshScript.rawValue, "generate Bash completion script"),
            (listDependencies.rawValue, "list all dependencies' names"),
            (listExecutables.rawValue, "list all executables' names"),
        ])
    }
}

extension SwiftPackageTool: ToolName {
    static var toolName: String {
        return "swift package"
    }
}
