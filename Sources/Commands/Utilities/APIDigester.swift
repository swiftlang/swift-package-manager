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

import _Concurrency
import Dispatch
import Foundation

import SPMBuildCore
import Basics
import CoreCommands
import PackageGraph
import PackageModel
import SourceControl
import Workspace

import protocol TSCBasic.DiagnosticLocation
import class Basics.AsyncProcess
import struct Basics.AsyncProcessResult
import func TSCBasic.withTemporaryFile

import enum TSCUtility.Diagnostics
import struct TSCUtility.SerializedDiagnostics
import var TSCUtility.verbosity

import SwiftParser
import SwiftSyntax

/// Helper for emitting a JSON API baseline for a module.
struct APIDigesterBaselineDumper {

    /// The revision to emit a baseline for.
    let baselineRevision: Revision

    /// The root package path.
    let packageRoot: AbsolutePath

    /// Parameters used when building end products.
    let productsBuildParameters: BuildParameters

    /// Parameters used when building tools (plugins and macros).
    let toolsBuildParameters: BuildParameters

    /// The API digester tool.
    let apiDigesterTool: SwiftAPIDigester

    /// The observabilityScope for emitting errors/warnings.
    let observabilityScope: ObservabilityScope

    init(
        baselineRevision: Revision,
        packageRoot: AbsolutePath,
        productsBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        apiDigesterTool: SwiftAPIDigester,
        observabilityScope: ObservabilityScope
    ) {
        self.baselineRevision = baselineRevision
        self.packageRoot = packageRoot
        self.productsBuildParameters = productsBuildParameters
        self.toolsBuildParameters = toolsBuildParameters
        self.apiDigesterTool = apiDigesterTool
        self.observabilityScope = observabilityScope
    }

    /// Emit the API baseline files and return the path to their directory.
    func emitAPIBaseline(
        for modulesToDiff: Set<String>,
        at baselineDir: AbsolutePath?,
        force: Bool,
        logLevel: Basics.Diagnostic.Severity,
        swiftCommandState: SwiftCommandState
    ) async throws -> AbsolutePath {
        var modulesToDiff = modulesToDiff
        let apiDiffDir = productsBuildParameters.apiDiff
        let baselineDir = (baselineDir ?? apiDiffDir).appending(component: baselineRevision.identifier)
        let baselinePath: (String)->AbsolutePath = { module in
            baselineDir.appending(component: module + ".json")
        }

        if !force {
            // Baselines which already exist don't need to be regenerated.
            modulesToDiff = modulesToDiff.filter {
                !swiftCommandState.fileSystem.exists(baselinePath($0))
            }
        }

        guard !modulesToDiff.isEmpty else {
            // If none of the baselines need to be regenerated, return.
            return baselineDir
        }

        // Setup a temporary directory where we can checkout and build the baseline treeish.
        let baselinePackageRoot = apiDiffDir.appending("\(baselineRevision.identifier)-checkout")
        if swiftCommandState.fileSystem.exists(baselinePackageRoot) {
            try swiftCommandState.fileSystem.removeFileTree(baselinePackageRoot)
        }

        // Clone the current package in a sandbox and checkout the baseline revision.
        let repositoryProvider = GitRepositoryProvider()
        let specifier = RepositorySpecifier(path: baselinePackageRoot)
        let workingCopy = try await repositoryProvider.createWorkingCopy(
            repository: specifier,
            sourcePath: packageRoot,
            at: baselinePackageRoot,
            editable: false
        )

        try workingCopy.checkout(revision: baselineRevision)

        // Create the workspace for this package.
        let workspace = try Workspace(
            forRootPackage: baselinePackageRoot,
            cancellator: swiftCommandState.cancellator
        )

        let graph = try await workspace.loadPackageGraph(
            rootPath: baselinePackageRoot,
            observabilityScope: self.observabilityScope
        )

        // Don't emit a baseline for a module that didn't exist yet in this revision.
        modulesToDiff.formIntersection(graph.apiDigesterModules)

        // Abort if we weren't able to load the package graph.
        if observabilityScope.errorsReported {
            throw Diagnostics.fatalError
        }

        // Update the data path input build parameters so it's built in the sandbox.
        var productsBuildParameters = productsBuildParameters
        productsBuildParameters.dataPath = workspace.location.scratchDirectory

        // Build the baseline module.
        // FIXME: We need to implement the build tool invocation closure here so that build tool plugins work with the APIDigester. rdar://86112934
        let buildSystem = try await swiftCommandState.createBuildSystem(
            explicitBuildSystem: .native,
            cacheBuildManifest: false,
            productsBuildParameters: productsBuildParameters,
            toolsBuildParameters: toolsBuildParameters,
            packageGraphLoader: { graph }
        )
        let buildResult = try await buildSystem.build(subset: .allExcludingTests, buildOutputs: [.buildPlan])

        guard let buildPlan = buildResult.buildPlan else {
            throw Diagnostics.fatalError
        }

        // Dump the SDK JSON.
        try swiftCommandState.fileSystem.createDirectory(baselineDir, recursive: true)

        let errors = await withTaskGroup(of: Error?.self) { group in
            for module in modulesToDiff {
                group.addTask {
                    do {
                        try apiDigesterTool.emitAPIBaseline(
                            to: baselinePath(module),
                            for: module,
                            buildPlan: buildPlan
                        )
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            return await group.compactMap { $0 }.reduce(into: []) {
                $0.append($1)
            }
        }

        for error in errors {
            observabilityScope.emit(error)
        }
        if observabilityScope.errorsReported {
            throw Diagnostics.fatalError
        }

        return baselineDir
    }
}

/// A wrapper for the swift-api-digester tool.
public struct SwiftAPIDigester {
    /// The file system to use
    let fileSystem: FileSystem

    /// The absolute path to `swift-api-digester` in the toolchain.
    let tool: AbsolutePath

    init(fileSystem: FileSystem, tool: AbsolutePath) {
        self.fileSystem = fileSystem
        self.tool = tool
    }

    /// Emit an API baseline file for the specified module at the specified location.
    public func emitAPIBaseline(
        to outputPath: AbsolutePath,
        for module: String,
        buildPlan: SPMBuildCore.BuildPlan
    ) throws {
        var args = ["-dump-sdk", "-compiler-style-diags"]
        args += try buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: false)
        args += ["-module", module, "-o", outputPath.pathString]

        let result = try runTool(args)

        if !self.fileSystem.exists(outputPath) {
            throw Error.failedToGenerateBaseline(module: module, output: (try? result.utf8Output()) ?? "", error: (try? result.utf8stderrOutput()) ?? "")
        }

        try self.fileSystem.readFileContents(outputPath).withData { data in
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String:Any] {
                guard let abiRoot = jsonObject["ABIRoot"] as? [String:Any] else {
                    throw Error.failedToValidateBaseline(module: module)
                }

                guard let symbols = abiRoot["children"] as? NSArray, symbols.count > 0 else {
                    throw Error.noSymbolsInBaseline(module: module, toolOutput: try result.utf8Output())
                }
            }
        }

    }

    /// Compare the current package API to a provided baseline file.
    public func compareAPIToBaseline(
        at baselinePath: AbsolutePath,
        for module: String,
        buildPlan: SPMBuildCore.BuildPlan,
        except breakageAllowlistPath: AbsolutePath?
    ) throws -> ComparisonResult? {
        var args = [
            "-diagnose-sdk",
            "-baseline-path", baselinePath.pathString,
            "-module", module
        ]
        args.append(contentsOf: try buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: false))
        if let breakageAllowlistPath {
            args.append(contentsOf: ["-breakage-allowlist-path", breakageAllowlistPath.pathString])
        }

        var comparisonResult = try withTemporaryFile(deleteOnClose: false) { file -> ComparisonResult? in
            args.append(contentsOf: ["-serialize-diagnostics-path", file.path.pathString])
            try runTool(args)
            let contents = try self.fileSystem.readFileContents(file.path)
            guard contents.count > 0 else {
                return nil
            }
            let serializedDiagnostics = try SerializedDiagnostics(bytes: contents)
            let apiDigesterCategory = "api-digester-breaking-change"
            let apiBreakingChanges = serializedDiagnostics.diagnostics
                .filter { $0.category == apiDigesterCategory }
                .map(BreakingChange.init)
            let otherDiagnostics = serializedDiagnostics.diagnostics
                .filter { $0.category != apiDigesterCategory }
            return ComparisonResult(moduleName: module,
                                    apiBreakingChanges: apiBreakingChanges,
                                    otherDiagnostics: otherDiagnostics)
        }

        // Check for removed @_exported imports
        let baselineExportedImports = Self.extractExportedImports(from: baselinePath, fileSystem: self.fileSystem)
        if !baselineExportedImports.isEmpty {
            let currentExportedImports = self.extractCurrentExportedImports(for: module, buildPlan: buildPlan)
            let removedExportedImports = baselineExportedImports.subtracting(currentExportedImports)
            if !removedExportedImports.isEmpty {
                let allowlist = Self.parseAllowlist(at: breakageAllowlistPath, fileSystem: self.fileSystem)
                var breakingChanges = comparisonResult?.apiBreakingChanges ?? []
                for dep in removedExportedImports.sorted() {
                    let changeText = "API breakage: @_exported import \(dep) has been removed"
                    if !Self.isAllowlisted(changeText, allowlist: allowlist) {
                        breakingChanges.append(BreakingChange(text: changeText))
                    }
                }
                if var res = comparisonResult {
                    res.apiBreakingChanges = breakingChanges
                    comparisonResult = res
                } else if !breakingChanges.isEmpty {
                    comparisonResult = ComparisonResult(
                        moduleName: module,
                        apiBreakingChanges: breakingChanges,
                        otherDiagnostics: []
                    )
                }
            }
        }

        return comparisonResult
    }

    private func extractCurrentExportedImports(
        for module: String,
        buildPlan: SPMBuildCore.BuildPlan
    ) -> Set<String> {
        if let dumped = try? withTemporaryFile(deleteOnClose: true, { file -> Set<String> in
            let path = try AbsolutePath(validating: file.path.pathString)
            var args = ["-dump-sdk", "-compiler-style-diags"]
            args += try buildPlan.createAPIToolCommonArgs(includeLibrarySearchPaths: false)
            args += ["-module", module, "-o", path.pathString]
            try runTool(args)
            return Self.extractExportedImports(from: path, fileSystem: self.fileSystem)
        }) {
            return dumped
        }

        for moduleDescription in buildPlan.buildModules {
            if moduleDescription.module.c99name == module,
               let swiftModule = moduleDescription.module.underlying as? SwiftModule {
                return Self.extractExportedImportsFromSources(
                    sources: swiftModule.sources.paths,
                    fileSystem: self.fileSystem
                )
            }
        }
        return []
    }

    public static func parseAllowlist(at path: AbsolutePath?, fileSystem: FileSystem) -> [String]? {
        guard let path,
              fileSystem.exists(path),
              let contents = try? fileSystem.readFileContents(path) else {
            return nil
        }
        var lines: [String] = []
        contents.withData { data in
            guard let string = String(data: data, encoding: .utf8) else { return }
            for line in string.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("//") && !trimmed.hasPrefix("#") {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }

    public static func isAllowlisted(_ breakageText: String, allowlist: [String]?) -> Bool {
        guard let allowlist else { return false }
        for line in allowlist {
            if breakageText.contains(line) || line.contains(breakageText) {
                return true
            }
        }
        return false
    }

    public static func extractExportedImports(
        from path: AbsolutePath,
        fileSystem: FileSystem
    ) -> Set<String> {
        guard fileSystem.exists(path),
              let contents = try? fileSystem.readFileContents(path) else {
            return []
        }
        var exportedImports = Set<String>()
        contents.withData { data in
            guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let abiRoot = json["ABIRoot"] as? [String: Any],
                  let children = abiRoot["children"] as? [Any] else {
                return
            }
            for child in children {
                guard let childDict = child as? [String: Any],
                      childDict["kind"] as? String == "Import",
                      let name = childDict["name"] as? String,
                      let declAttributes = childDict["declAttributes"] as? [String],
                      declAttributes.contains("Exported") else {
                    continue
                }
                exportedImports.insert(name)
            }
        }
        return exportedImports
    }

    public static func extractExportedImportsFromSources(
        sources: [AbsolutePath],
        fileSystem: FileSystem
    ) -> Set<String> {
        var exportedImports = Set<String>()
        for sourcePath in sources {
            guard sourcePath.extension == "swift",
                  let contents = try? fileSystem.readFileContents(sourcePath) else {
                continue
            }
            contents.withData { data in
                guard let sourceText = String(data: data, encoding: .utf8) else { return }
                guard sourceText.contains("_exported") else { return }
                let sourceFile = Parser.parse(source: sourceText)
                for statement in sourceFile.statements {
                    if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                        let isExported = importDecl.attributes.contains { attr in
                            if case .attribute(let a) = attr {
                                return a.attributeName.trimmedDescription == "_exported"
                            }
                            return false
                        }
                        if isExported, let firstComponent = importDecl.path.first {
                            exportedImports.insert(firstComponent.name.text)
                        }
                    }
                }
            }
        }
        return exportedImports
    }

    @discardableResult private func runTool(_ args: [String]) throws -> AsyncProcessResult {
        let arguments = [tool.pathString] + args
        let process = AsyncProcess(
            arguments: arguments,
            outputRedirection: .collect(redirectStderr: true)
        )
        try process.launch()
        return try process.waitUntilExit()
    }
}

extension SwiftAPIDigester {
    public enum Error: Swift.Error, CustomStringConvertible {
        case failedToGenerateBaseline(module: String, output: String, error: String)
        case failedToValidateBaseline(module: String)
        case noSymbolsInBaseline(module: String, toolOutput: String)

        public var description: String {
            switch self {
            case .failedToGenerateBaseline(let module, let output, let error):
                return "failed to generate baseline for \(module) (output: \(output), error: \(error)"
            case .failedToValidateBaseline(let module):
                return "failed to validate baseline for \(module)"
            case .noSymbolsInBaseline(let module, let toolOutput):
                return "baseline for \(module) contains no symbols, swift-api-digester output: \(toolOutput)"
            }
        }
    }
}

extension SwiftAPIDigester {
    /// A breaking change detected when comparing against an API baseline.
    public struct BreakingChange: Sendable, Equatable {
        /// The description of the breaking change.
        public var text: String

        public init(text: String) {
            self.text = text
        }

        public init(diagnostic: SerializedDiagnostics.Diagnostic) {
            self.text = diagnostic.text
        }
    }

    /// The result of comparing a module's API to a provided baseline.
    public struct ComparisonResult {
        /// The name of the module being diffed.
        var moduleName: String
        /// Breaking changes made to the API since the baseline was generated.
        var apiBreakingChanges: [BreakingChange]
        /// Other diagnostics emitted while comparing the current API to the baseline.
        var otherDiagnostics: [SerializedDiagnostics.Diagnostic]

        /// `true` if the comparison succeeded and no breaking changes were found, otherwise `false`.
        var hasNoAPIBreakingChanges: Bool {
            apiBreakingChanges.isEmpty && otherDiagnostics.filter { [.fatal, .error].contains($0.level) }.isEmpty
        }
    }
}


extension BuildParameters {
    /// The directory containing artifacts for API diffing operations.
    var apiDiff: AbsolutePath {
        dataPath.appending("apidiff")
    }
}

extension ModulesGraph {
    /// The list of modules that should be used as an input to the API digester.
    var apiDigesterModules: [String] {
        self.rootPackages
            .flatMap(\.products)
            .filter { $0.type.isLibrary }
            .flatMap(\.modules)
            .filter { $0.underlying is SwiftModule }
            .map { $0.c99name }
    }
}

extension SerializedDiagnostics.SourceLocation {
    public var description: String {
        return "\(filename):\(line):\(column)"
    }
}

extension SerializedDiagnostics.SourceLocation: @retroactive DiagnosticLocation {}

