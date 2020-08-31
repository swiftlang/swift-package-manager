/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import TSCUtility
import SPMLLBuild
import PackageModel
import Dispatch
import Foundation
import LLBuildManifest
import SPMBuildCore

typealias Diagnostic = TSCBasic.Diagnostic

class CustomLLBuildCommand: SPMLLBuild.ExternalCommand {
    let ctx: BuildExecutionContext

    required init(_ ctx: BuildExecutionContext) {
        self.ctx = ctx
    }

    func getSignature(_ command: SPMLLBuild.Command) -> [UInt8] {
        return []
    }

    func execute(
        _ command: SPMLLBuild.Command,
        _ buildSystemCommandInterface: SPMLLBuild.BuildSystemCommandInterface
    ) -> Bool {
        fatalError("subclass responsibility")
    }
}

final class TestDiscoveryCommand: CustomLLBuildCommand {

    private func write(
        tests: [IndexStore.TestCaseClass],
        forModule module: String,
        to path: AbsolutePath
    ) throws {
        let stream = try LocalFileOutputByteStream(path)

        stream <<< "import XCTest" <<< "\n"
        stream <<< "@testable import " <<< module <<< "\n"

        for klass in tests {
            stream <<< "\n"
            stream <<< "fileprivate extension " <<< klass.name <<< " {" <<< "\n"
            stream <<< indent(4) <<< "static let __allTests__\(klass.name) = [" <<< "\n"
            for method in klass.methods {
                let method = method.hasSuffix("()") ? String(method.dropLast(2)) : method
                stream <<< indent(8) <<< "(\"\(method)\", \(method))," <<< "\n"
            }
            stream <<< indent(4) <<< "]" <<< "\n"
            stream <<< "}" <<< "\n"
        }

        stream <<< """
        func __allTests_\(module)() -> [XCTestCaseEntry] {
            return [\n
        """

        for klass in tests {
            stream <<< indent(8) <<< "testCase(\(klass.name).__allTests__\(klass.name)),\n"
        }

        stream <<< """
            ]
        }
        """

        stream.flush()
    }

    private func execute(with tool: LLBuildManifest.TestDiscoveryTool) throws {
        let index = ctx.buildParameters.indexStore
        let api = try ctx.indexStoreAPI.get()
        let store = try IndexStore.open(store: index, api: api)

        // FIXME: We can speed this up by having one llbuild command per object file.
        let tests = try tool.inputs.flatMap {
            try store.listTests(inObjectFile: AbsolutePath($0.name))
        }

        let outputs = tool.outputs.compactMap{ try? AbsolutePath(validating: $0.name) }
        let testsByModule = Dictionary(grouping: tests, by: { $0.module })

        func isMainFile(_ path: AbsolutePath) -> Bool {
            return path.basename == "main.swift"
        }

        var mainFile: AbsolutePath?
        // Write one file for each test module.
        //
        // We could write everything in one file but that can easily run into type conflicts due
        // in complex packages with large number of test targets.
        for file in outputs {
            if mainFile == nil && isMainFile(file) {
                mainFile = file
                continue 
            }

            // FIXME: This is relying on implementation detail of the output but passing the
            // the context all the way through is not worth it right now.
            let module = file.basenameWithoutExt

            guard let tests = testsByModule[module] else {
                // This module has no tests so just write an empty file for it.
                try localFileSystem.writeFileContents(file, bytes: "")
                continue
            }
            try write(tests: tests, forModule: module, to: file)
        }

        // Write the main file.
        let stream = try LocalFileOutputByteStream(mainFile!)

        stream <<< "import XCTest" <<< "\n\n"
        stream <<< "var tests = [XCTestCaseEntry]()" <<< "\n"
        for module in testsByModule.keys {
            stream <<< "tests += __allTests_\(module)()" <<< "\n"
        }
        stream <<< "\n"
        stream <<< "XCTMain(tests)" <<< "\n"

        stream.flush()
    }

    private func indent(_ spaces: Int) -> ByteStreamable {
        return Format.asRepeating(string: " ", count: spaces)
    }

    override func execute(
        _ command: SPMLLBuild.Command,
        _ buildSystemCommandInterface: SPMLLBuild.BuildSystemCommandInterface
    ) -> Bool {
        // This tool will never run without the build description.
        let buildDescription = ctx.buildDescription!
        guard let tool = buildDescription.testDiscoveryCommands[command.name] else {
            print("command \(command.name) not registered")
            return false
        }
        do {
            try execute(with: tool)
        } catch {
            // FIXME: Shouldn't use "print" here.
            print("error:", error)
            return false
        }
        return true
    }
}

private final class InProcessTool: Tool {
    let ctx: BuildExecutionContext
    let type: CustomLLBuildCommand.Type

    init(_ ctx: BuildExecutionContext, type: CustomLLBuildCommand.Type) {
        self.ctx = ctx
        self.type = type
    }

    func createCommand(_ name: String) -> ExternalCommand {
        return type.init(ctx)
    }
}

/// Contains the description of the build that is needed during the execution.
public struct BuildDescription: Codable {
    public typealias CommandName = String
    public typealias TargetName = String

    /// The Swift compiler invocation targets.
    let swiftCommands: [BuildManifest.CmdName : SwiftCompilerTool]

    /// The Swift compiler frontend invocation targets.
    let swiftFrontendCommands: [BuildManifest.CmdName : SwiftFrontendTool]

    /// The map of test discovery commands.
    let testDiscoveryCommands: [BuildManifest.CmdName: LLBuildManifest.TestDiscoveryTool]

    /// The map of copy commands.
    let copyCommands: [BuildManifest.CmdName: LLBuildManifest.CopyTool]

    /// The built test products.
    public let builtTestProducts: [BuiltTestProduct]

    public init(
        plan: BuildPlan,
        swiftCommands: [BuildManifest.CmdName : SwiftCompilerTool],
        swiftFrontendCommands: [BuildManifest.CmdName : SwiftFrontendTool],
        testDiscoveryCommands: [BuildManifest.CmdName: LLBuildManifest.TestDiscoveryTool],
        copyCommands: [BuildManifest.CmdName: LLBuildManifest.CopyTool]
    ) {
        self.swiftCommands = swiftCommands
        self.swiftFrontendCommands = swiftFrontendCommands
        self.testDiscoveryCommands = testDiscoveryCommands
        self.copyCommands = copyCommands

        self.builtTestProducts = plan.buildProducts.filter{ $0.product.type == .test }.map { desc in
            // FIXME(perf): Provide faster lookups.
            let package = plan.graph.packages.first{ $0.products.contains(desc.product) }!
            return BuiltTestProduct(
                packageName: package.name,
                productName: desc.product.name,
                binaryPath: desc.binary
            )
        }
    }

    public func write(to path: AbsolutePath) throws {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(self)
        try localFileSystem.writeFileContents(path, bytes: ByteString(data))
    }

    public static func load(from path: AbsolutePath) throws -> BuildDescription {
        let contents = try localFileSystem.readFileContents(path).contents
        return try JSONDecoder().decode(BuildDescription.self, from: Data(contents))
    }
}

/// The context available during build execution.
public final class BuildExecutionContext {

    /// Reference to the index store API.
    var indexStoreAPI: Result<IndexStoreAPI, Error> {
        indexStoreAPICache.getValue(self)
    }

    /// The build parameters.
    let buildParameters: BuildParameters

    /// The build description.
    ///
    /// This is optional because we might not have a valid build description when performing the
    /// build for PackageStructure target.
    let buildDescription: BuildDescription?

    /// The package structure delegate.
    let packageStructureDelegate: PackageStructureDelegate

    public init(
        _ buildParameters: BuildParameters,
        buildDescription: BuildDescription? = nil,
        packageStructureDelegate: PackageStructureDelegate
    ) {
        self.buildParameters = buildParameters
        self.buildDescription = buildDescription
        self.packageStructureDelegate = packageStructureDelegate
    }

    // MARK:- Private

    private var indexStoreAPICache = LazyCache(createIndexStoreAPI)
    private func createIndexStoreAPI() -> Result<IndexStoreAPI, Error> {
        Result {
            let ext = buildParameters.hostTriple.dynamicLibraryExtension
            let indexStoreLib = buildParameters.toolchain.toolchainLibDir.appending(component: "libIndexStore" + ext)
            return try IndexStoreAPI(dylib: indexStoreLib)
        }
    }
}

public protocol PackageStructureDelegate {
    func packageStructureChanged() -> Bool
}

final class PackageStructureCommand: CustomLLBuildCommand {

    override func getSignature(_ command: SPMLLBuild.Command) -> [UInt8] {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }

        // Include build parameters and process env in the signature.
        var hash = Data()
        hash += try! encoder.encode(self.ctx.buildParameters)
        hash += try! encoder.encode(ProcessEnv.vars)
        return [UInt8](hash)
    }

    override func execute(
        _ command: SPMLLBuild.Command,
        _ commandInterface: SPMLLBuild.BuildSystemCommandInterface
    ) -> Bool {
        return self.ctx.packageStructureDelegate.packageStructureChanged()
    }
}

final class CopyCommand: CustomLLBuildCommand {
    override func execute(
        _ command: SPMLLBuild.Command,
        _ commandInterface: SPMLLBuild.BuildSystemCommandInterface
    ) -> Bool {
        // This tool will never run without the build description.
        let buildDescription = ctx.buildDescription!
        guard let tool = buildDescription.copyCommands[command.name] else {
            print("command \(command.name) not registered")
            return false
        }

        do {
            let input = AbsolutePath(tool.inputs[0].name)
            let output = AbsolutePath(tool.outputs[0].name)
            try localFileSystem.createDirectory(output.parentDirectory, recursive: true)
            try localFileSystem.removeFileTree(output)
            try localFileSystem.copy(from: input, to: output)
        } catch {
            // FIXME: Shouldn't use "print" here.
            print("error:", error)
            return false
        }
        return true
    }
}

public final class BuildDelegate: BuildSystemDelegate, SwiftCompilerOutputParserDelegate {
    private let diagnostics: DiagnosticsEngine
    public var outputStream: ThreadSafeOutputByteStream
    public var progressAnimation: ProgressAnimationProtocol
    public var onCommmandFailure: (() -> Void)?
    public var isVerbose: Bool = false
    private let queue = DispatchQueue(label: "org.swift.swiftpm.build-delegate")
    private var taskTracker = CommandTaskTracker()
    
    /// Swift parsers keyed by llbuild command name.
    private var swiftParsers: [String: SwiftCompilerOutputParser] = [:]

    /// The build execution context.
    private let buildExecutionContext: BuildExecutionContext

    public init(
        bctx: BuildExecutionContext,
        diagnostics: DiagnosticsEngine,
        outputStream: OutputByteStream,
        progressAnimation: ProgressAnimationProtocol
    ) {
        self.diagnostics = diagnostics
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.outputStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.progressAnimation = progressAnimation
        self.buildExecutionContext = bctx

        let swiftParsers = bctx.buildDescription?.swiftCommands.mapValues { tool in
            SwiftCompilerOutputParser(targetName: tool.moduleName, delegate: self)
        } ?? [:]
        self.swiftParsers = swiftParsers
    }

    public var fs: SPMLLBuild.FileSystem? {
        return nil
    }

    public func lookupTool(_ name: String) -> Tool? {
        switch name {
        case TestDiscoveryTool.name:
            return InProcessTool(buildExecutionContext, type: TestDiscoveryCommand.self)
        case PackageStructureTool.name:
            return InProcessTool(buildExecutionContext, type: PackageStructureCommand.self)
        case CopyTool.name:
            return InProcessTool(buildExecutionContext, type: CopyCommand.self)
        default:
            return nil
        }
    }

    public func hadCommandFailure() {
        onCommmandFailure?()
    }

    public func handleDiagnostic(_ diagnostic: SPMLLBuild.Diagnostic) {
        switch diagnostic.kind {
        case .note:
            diagnostics.emit(note: diagnostic.message)
        case .warning:
            diagnostics.emit(warning: diagnostic.message)
        case .error:
            diagnostics.emit(error: diagnostic.message)
        @unknown default:
            diagnostics.emit(note: diagnostic.message)
        }
    }

    public func commandStatusChanged(_ command: SPMLLBuild.Command, kind: CommandStatusKind) {
        guard !isVerbose else { return }
        guard command.shouldShowStatus else { return }
        guard !swiftParsers.keys.contains(command.name) else { return }

        queue.async {
            self.taskTracker.commandStatusChanged(command, kind: kind)
            self.updateProgress()
        }
    }

    public func commandPreparing(_ command: SPMLLBuild.Command) {
    }

    public func commandStarted(_ command: SPMLLBuild.Command) {
        guard command.shouldShowStatus else { return }

        queue.async {
            if self.isVerbose {
                self.outputStream <<< command.verboseDescription <<< "\n"
                self.outputStream.flush()
            }
        }
    }

    public func shouldCommandStart(_ command: SPMLLBuild.Command) -> Bool {
        return true
    }

    public func commandFinished(_ command: SPMLLBuild.Command, result: CommandResult) {
        guard !isVerbose else { return }
        guard command.shouldShowStatus else { return }
        guard !swiftParsers.keys.contains(command.name) else { return }

        queue.async {
            let targetName = self.swiftParsers[command.name]?.targetName
            self.taskTracker.commandFinished(command, result: result, targetName: targetName)
            self.updateProgress()
        }
    }

    public func commandHadError(_ command: SPMLLBuild.Command, message: String) {
        diagnostics.emit(error: message)
    }

    public func commandHadNote(_ command: SPMLLBuild.Command, message: String) {
        // FIXME: This is wrong.
        diagnostics.emit(warning: message)
    }

    public func commandHadWarning(_ command: SPMLLBuild.Command, message: String) {
        diagnostics.emit(warning: message)
    }

    public func commandCannotBuildOutputDueToMissingInputs(
        _ command: SPMLLBuild.Command,
        output: BuildKey,
        inputs: [BuildKey]
    ) {
        diagnostics.emit(.missingInputs(output: output, inputs: inputs))
    }

    public func cannotBuildNodeDueToMultipleProducers(output: BuildKey, commands: [SPMLLBuild.Command]) {
        diagnostics.emit(.multipleProducers(output: output, commands: commands))
    }

    public func commandProcessStarted(_ command: SPMLLBuild.Command, process: ProcessHandle) {
    }

    public func commandProcessHadError(_ command: SPMLLBuild.Command, process: ProcessHandle, message: String) {
        diagnostics.emit(.commandError(command: command, message: message))
    }

    public func commandProcessHadOutput(_ command: SPMLLBuild.Command, process: ProcessHandle, data: [UInt8]) {
        guard command.shouldShowStatus else { return }

        if let swiftParser = swiftParsers[command.name] {
            swiftParser.parse(bytes: data)
        } else {
            queue.async {
                self.progressAnimation.clear()
                self.outputStream <<< data
                self.outputStream.flush()
            }
        }
    }

    public func commandProcessFinished(
        _ command: SPMLLBuild.Command,
        process: ProcessHandle,
        result: CommandExtendedResult
    ) {
    }

    public func cycleDetected(rules: [BuildKey]) {
        diagnostics.emit(.cycleError(rules: rules))
    }

    public func shouldResolveCycle(rules: [BuildKey], candidate: BuildKey, action: CycleAction) -> Bool {
        return false
    }

    public func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage) {
        queue.async {
            if self.isVerbose {
                if let text = message.verboseProgressText {
                    self.outputStream <<< text <<< "\n"
                    self.outputStream.flush()
                }
            } else {
                self.taskTracker.swiftCompilerDidOuputMessage(message, targetName: parser.targetName)
                self.updateProgress()
            }

            if let output = message.standardOutput {
                if !self.isVerbose {
                    self.progressAnimation.clear()
                }

                self.outputStream <<< output
                self.outputStream.flush()
            }
        }
    }

    public func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics.emit(.swiftCompilerOutputParsingError(message))
        onCommmandFailure?()
    }

    private func updateProgress() {
        if let progressText = taskTracker.latestFinishedText {
            progressAnimation.update(
                step: taskTracker.finishedCount,
                total: taskTracker.totalCount,
                text: progressText)
        }
    }
}

/// Tracks tasks based on command status and swift compiler output.
fileprivate struct CommandTaskTracker {
    private(set) var totalCount = 0
    private(set) var finishedCount = 0
    private var swiftTaskProgressTexts: [Int: String] = [:]

    /// The last task text before the task list was emptied.
    private(set) var latestFinishedText: String?

    mutating func commandStatusChanged(_ command: SPMLLBuild.Command, kind: CommandStatusKind) {
        switch kind {
        case .isScanning:
            totalCount += 1
            break
        case .isUpToDate:
            totalCount -= 1
            break
        case .isComplete:
            break
        @unknown default:
            assertionFailure("unhandled command status kind \(kind) for command \(command)")
            break
        }
    }
    
    mutating func commandFinished(_ command: SPMLLBuild.Command, result: CommandResult, targetName: String?) {
        latestFinishedText = progressText(of: command, targetName: targetName)

        switch result {
        case .succeeded, .skipped:
            finishedCount += 1
        case .cancelled, .failed:
            break
        default:
            break
        }
    }
    
    mutating func swiftCompilerDidOuputMessage(_ message: SwiftCompilerMessage, targetName: String) {
        switch message.kind {
        case .began(let info):
            if let text = progressText(of: message, targetName: targetName) {
                swiftTaskProgressTexts[info.pid] = text
            }

            totalCount += 1
        case .finished(let info):
            if let progressText = swiftTaskProgressTexts[info.pid] {
                latestFinishedText = progressText
                swiftTaskProgressTexts[info.pid] = nil
            }

            finishedCount += 1
        case .unparsableOutput, .signalled, .skipped:
            break
        }
    }

    private func progressText(of command: SPMLLBuild.Command, targetName: String?) -> String {
        // Transforms descriptions like "Linking ./.build/x86_64-apple-macosx/debug/foo" into "Linking foo".
        if let firstSpaceIndex = command.description.firstIndex(of: " "),
           let lastDirectorySeperatorIndex = command.description.lastIndex(of: "/")
        {
            let action = command.description[..<firstSpaceIndex]
            let fileNameStartIndex = command.description.index(after: lastDirectorySeperatorIndex)
            let fileName = command.description[fileNameStartIndex...]

            if let targetName = targetName {
                return "\(action) \(targetName) \(fileName)"
            } else {
                return "\(action) \(fileName)"
            }
        } else {
            return command.description
        }
    }

    private func progressText(of message: SwiftCompilerMessage, targetName: String) -> String? {
        if case .began(let info) = message.kind {
            switch message.name {
            case "compile":
                if let sourceFile = info.inputs.first {
                    return "Compiling \(targetName) \(AbsolutePath(sourceFile).components.last!)"
                }
            case "link":
                return "Linking \(targetName)"
            case "merge-module":
                return "Merging module \(targetName)"
            case "generate-dsym":
                return "Generating \(targetName) dSYM"
            case "generate-pch":
                return "Generating \(targetName) PCH"
            default:
                break
            }
        }

        return nil
    }
}

extension SwiftCompilerMessage {
    fileprivate var verboseProgressText: String? {
        switch kind {
        case .began(let info):
            return ([info.commandExecutable] + info.commandArguments).joined(separator: " ")
        case .skipped, .finished, .signalled, .unparsableOutput:
            return nil
        }
    }

    fileprivate var standardOutput: String? {
        switch kind {
        case .finished(let info),
             .signalled(let info):
            return info.output
        case .unparsableOutput(let output):
            return output
        case .skipped, .began:
            return nil
        }
    }
}

private extension Diagnostic.Message {
    static func cycleError(rules: [BuildKey]) -> Diagnostic.Message {
        .error("build cycle detected: " + rules.map{ $0.key }.joined(separator: ", "))
    }

    static func missingInputs(output: BuildKey, inputs: [BuildKey]) -> Diagnostic.Message {
        let missingInputs = inputs.map{ $0.key }.joined(separator: ", ")
        return .error("couldn't build \(output.key) because of missing inputs: \(missingInputs)")
    }

    static func multipleProducers(output: BuildKey, commands: [SPMLLBuild.Command]) -> Diagnostic.Message {
        let producers = commands.map{ $0.description }.joined(separator: ", ")
        return .error("couldn't build \(output.key) because of missing producers: \(producers)")
    }

    static func commandError(command: SPMLLBuild.Command, message: String) -> Diagnostic.Message {
        .error("command \(command.description) failed: \(message)")
    }

    static func swiftCompilerOutputParsingError(_ error: String) -> Diagnostic.Message {
        .error("failed parsing the Swift compiler output: \(error)")
    }
}
