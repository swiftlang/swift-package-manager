/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Basics
import TSCBasic
import PackageModel
import PackageGraph
import SourceControl
import Workspace
import Foundation
import PackageSyntax
import PackageLoading
import TSCUtility

@main
public struct SwiftPackageEditorTool: ParsableCommand {
    public static var configuration = CommandConfiguration(
        commandName: "package-editor",
        _superCommandName: "swift",
        abstract: "Edit Package.swift files",
        version: SwiftVersion.current.completeDisplayString,
        subcommands: [AddDependency.self, AddTarget.self, AddProduct.self],
        helpNames: [.short, .long, .customLong("help", withSingleDash: true)])
    public init() {}
}

final class EditorTool {
    let diagnostics: DiagnosticsEngine
    let packageRoot: AbsolutePath
    let toolchain: UserToolchain
    let packageEditor: PackageEditor
    private var cachedPackageGraph: PackageGraph?

    init() throws {
        diagnostics = DiagnosticsEngine(handlers: [print(diagnostic:)])

        guard let cwd = localFileSystem.currentWorkingDirectory else {
            diagnostics.emit(.error("could not determine current working directory"))
            throw ExitCode.failure
        }

        var root = cwd
        while !localFileSystem.isFile(root.appending(component: Manifest.filename)) {
            root = root.parentDirectory
            guard !root.isRoot else {
                diagnostics.emit(.error("could not find package manifest"))
                throw ExitCode.failure
            }
        }
        packageRoot = root

        toolchain = try UserToolchain(destination: Destination.hostDestination(originalWorkingDirectory: cwd))

        let manifestPath = try ManifestLoader.findManifest(packagePath: packageRoot,
                                                           fileSystem: localFileSystem,
                                                           currentToolsVersion: ToolsVersion.current)
        let repositoryManager = RepositoryManager(fileSystem: localFileSystem,
                                                  path: packageRoot.appending(component: ".build"),
                                                  provider: GitRepositoryProvider(),
                                                  initializationWarningHandler: { _ in })
        packageEditor = try PackageEditor(manifestPath: manifestPath,
                                          repositoryManager: repositoryManager,
                                          toolchain: toolchain,
                                          diagnosticsEngine: diagnostics)
    }

    func loadPackageGraph() throws -> PackageGraph {
        if let cachedPackageGraph = cachedPackageGraph {
            return cachedPackageGraph
        }
        let workspace = try Workspace.init(forRootPackage: packageRoot, customManifestLoader: nil)
        let observability = ObservabilitySystem { _, _ in }
        let graph = try workspace.loadPackageGraph(rootPath: packageRoot, observabilityScope: observability.topScope)
        guard !diagnostics.hasErrors else {
            throw ExitCode.failure
        }
        cachedPackageGraph = graph
        return graph
    }
}

protocol EditorCommand: ParsableCommand {
    func run(_ editorTool: EditorTool) throws
}

extension EditorCommand {
    public func run() throws {
        let editorTool = try EditorTool()
        try self.run(editorTool)
        if editorTool.diagnostics.hasErrors {
            throw ExitCode.failure
        }
    }
}

struct AddDependency: EditorCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a dependency to the current package.")

    @Argument(help: "The URL of a remote package, or the path to a local package")
    var dependencyURL: String

    @Option(help: "Specifies an exact package version requirement")
    var exact: Version?

    @Option(help: "Specifies a package revision requirement")
    var revision: String?

    @Option(help: "Specifies a package branch requirement")
    var branch: String?

    @Option(help: "Specifies a package version requirement from the specified version up to the next major version")
    var from: Version?

    @Option(help: "Specifies a package version requirement from the specified version up to the next minor version")
    var upToNextMinorFrom: Version?

    @Option(help: "Specifies the upper bound of a range-based package version requirement")
    var to: Version?

    @Option(help: "Specifies the upper bound of a closed range-based package version requirement")
    var through: Version?

    func run(_ editorTool: EditorTool) throws {
        var requirements: [PackageDependencyRequirement] = []
        if let exactVersion = exact {
            requirements.append(.exact(exactVersion.description))
        }
        if let revision = revision {
            requirements.append(.revision(revision))
        }
        if let branch = branch {
            requirements.append(.branch(branch))
        }
        if let version = from {
            requirements.append(.upToNextMajor(version.description))
        }
        if let version = upToNextMinorFrom {
            requirements.append(.upToNextMinor(version.description))
        }

        guard requirements.count <= 1 else {
            editorTool.diagnostics.emit(.error("only one requirement is allowed when specifiying a dependency"))
            throw ExitCode.failure
        }

        var requirement = requirements.first

        if case .upToNextMajor(let rangeStart) = requirement {
            guard to == nil || through == nil else {
                editorTool.diagnostics.emit(.error("'--to' and '--through' may not be used in the same requirement"))
                throw ExitCode.failure
            }
            if let rangeEnd = to {
                requirement = .range(rangeStart.description, rangeEnd.description)
            } else if let closedRangeEnd = through {
                requirement = .closedRange(rangeStart.description, closedRangeEnd.description)
            }
        } else {
            guard to == nil, through == nil else {
                editorTool.diagnostics.emit(.error("'--to' and '--through' may only be used with '--from' to specify a range requirement"))
                throw ExitCode.failure
            }
        }

        do {
            try editorTool.packageEditor.addPackageDependency(url: dependencyURL, requirement: requirement)
        } catch Diagnostics.fatalError {
            throw ExitCode.failure
        }
    }
}

struct AddTarget: EditorCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a target to the current package.")

    @Argument(help: "The name of the new target")
    var name: String

    @Option(help: "The type of the new target (library, executable, test, or binary)")
    var type: String = "library"

    @Flag(help: "If present, no corresponding test target will be created for a new library target")
    var noTestTarget: Bool = false

    @Option(parsing: .upToNextOption,
            help: "A list of target dependency names (targets and/or dependency products)")
    var dependencies: [String] = []

    @Option(help: "The URL for a remote binary target")
    var url: String?

    @Option(help: "The checksum for a remote binary target")
    var checksum: String?

    @Option(help: "The path for a local binary target")
    var path: String?

    func run(_ editorTool: EditorTool) throws {
        let newTarget: NewTarget
        switch type {
        case "library":
            try verifyNoTargetBinaryOptionsPassed(diagnostics: editorTool.diagnostics)
            newTarget = .library(name: name,
                                 includeTestTarget: !noTestTarget,
                                 dependencyNames: dependencies)
        case "executable":
            try verifyNoTargetBinaryOptionsPassed(diagnostics: editorTool.diagnostics)
            newTarget = .executable(name: name,
                                    dependencyNames: dependencies)
        case "test":
            try verifyNoTargetBinaryOptionsPassed(diagnostics: editorTool.diagnostics)
            newTarget = .test(name: name,
                              dependencyNames: dependencies)
        case "binary":
            guard dependencies.isEmpty else {
                editorTool.diagnostics.emit(.error("option '--dependencies' is not supported for binary targets"))
                throw ExitCode.failure
            }
            // This check is somewhat forgiving, and does the right thing if
            // the user passes a url with --path or a path with --url.
            guard let urlOrPath = url ?? path, url == nil || path == nil else {
                editorTool.diagnostics.emit(.error("binary targets must specify either a path or both a URL and a checksum"))
                throw ExitCode.failure
            }
            newTarget = .binary(name: name,
                                urlOrPath: urlOrPath,
                                checksum: checksum)
        default:
            editorTool.diagnostics.emit(.error("unsupported target type '\(type)'; supported types are library, executable, test, and binary"))
            throw ExitCode.failure
        }

        do {
            let mapping = try createProductPackageNameMapping(packageGraph: editorTool.loadPackageGraph())
            try editorTool.packageEditor.addTarget(newTarget, productPackageNameMapping: mapping)
        } catch Diagnostics.fatalError {
            throw ExitCode.failure
        }
    }

    private func createProductPackageNameMapping(packageGraph: PackageGraph) throws -> [String: TextualPackageReference] {
        var productPackageNameMapping: [String: TextualPackageReference] = [:]
        for dependencyPackage in packageGraph.rootPackages.flatMap(\.dependencies) {
            for product in dependencyPackage.products {
                productPackageNameMapping[product.name] = TextualPackageReference(dependencyPackage)
            }
        }
        return productPackageNameMapping
    }

    private func verifyNoTargetBinaryOptionsPassed(diagnostics: DiagnosticsEngine) throws {
        guard url == nil else {
            diagnostics.emit(.error("option '--url' is only supported for binary targets"))
            throw ExitCode.failure
        }
        guard path == nil else {
            diagnostics.emit(.error("option '--path' is only supported for binary targets"))
            throw ExitCode.failure
        }
        guard checksum == nil else {
            diagnostics.emit(.error("option '--checksum' is only supported for binary targets"))
            throw ExitCode.failure
        }
    }
}

struct AddProduct: EditorCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a product to the current package.")

    @Argument(help: "The name of the new product")
    var name: String

    @Option(help: "The type of the new product (library, static-library, dynamic-library, or executable)")
    var type: ProductType?

    @Option(parsing: .upToNextOption,
            help: "A list of target names to add to the new product")
    var targets: [String]

    func run(_ editorTool: EditorTool) throws {
        do {
            try editorTool.packageEditor.addProduct(name: name, type: type ?? .library(.automatic), targets: targets)
        } catch Diagnostics.fatalError {
            throw ExitCode.failure
        }
    }
}

extension Version: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}

extension ProductType: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "library":
            self = .library(.automatic)
        case "static-library":
            self = .library(.static)
        case "dynamic-library":
            self = .library(.dynamic)
        case "executable":
            self = .executable
        default:
            return nil
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        .list(["library", "static-library", "dynamic-library", "executable"])
    }
}

func print(diagnostic: TSCBasic.Diagnostic) {
    if !(diagnostic.location is UnknownLocation) {
        stderrStream <<< diagnostic.location.description <<< ": "
    }
    switch diagnostic.message.behavior {
    case .error:
        stderrStream <<< "error: "
    case .warning:
        stderrStream <<< "warning: "
    case .note:
        stderrStream <<< "note"
    case .remark:
        stderrStream <<< "remark: "
    case .ignored:
        break
    }
    stderrStream <<< diagnostic.description <<< "\n"
    stderrStream.flush()
}
