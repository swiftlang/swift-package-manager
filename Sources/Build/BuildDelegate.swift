/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2018 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic
import SPMUtility
import SPMLLBuild
import Dispatch
import Foundation

/// Diagnostic error when a llbuild command encounters an error.
struct LLBuildCommandErrorDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildCommandErrorDiagnostic.self,
        name: "org.swift.diags.llbuild-command-error",
        defaultBehavior: .error,
        description: { $0 <<< { $0.message } }
    )

    let message: String
}

/// Diagnostic warning when a llbuild command encounters a warning.
struct LLBuildCommandWarningDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildCommandWarningDiagnostic.self,
        name: "org.swift.diags.llbuild-command-warning",
        defaultBehavior: .warning,
        description: { $0 <<< { $0.message } }
    )

    let message: String
}

/// Diagnostic note when a llbuild command encounters a warning.
struct LLBuildCommandNoteDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildCommandNoteDiagnostic.self,
        name: "org.swift.diags.llbuild-command-note",
        defaultBehavior: .note,
        description: { $0 <<< { $0.message } }
    )

    let message: String
}

/// Diagnostic error when llbuild detects a cycle.
struct LLBuildCycleErrorDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildCycleErrorDiagnostic.self,
        name: "org.swift.diags.llbuild-cycle",
        defaultBehavior: .error,
        description: {
            $0 <<< "build cycle detected: "
            $0 <<< { $0.rules.map({ $0.key }).joined(separator: ", ") }
        }
    )

    let rules: [BuildKey]
}

/// Diagnostic error from llbuild
struct LLBuildErrorDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildErrorDiagnostic.self,
        name: "org.swift.diags.llbuild-error",
        defaultBehavior: .error,
        description: {
            $0 <<< { $0.message }
        }
    )

    let message: String
}

/// Diagnostic warning from llbuild
struct LLBuildWarningDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildWarningDiagnostic.self,
        name: "org.swift.diags.llbuild-warning",
        defaultBehavior: .warning,
        description: {
            $0 <<< { $0.message }
        }
    )

    let message: String
}

/// Diagnostic note from llbuild
struct LLBuildNoteDiagnostic: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildNoteDiagnostic.self,
        name: "org.swift.diags.llbuild-note",
        defaultBehavior: .note,
        description: {
            $0 <<< { $0.message }
        }
    )

    let message: String
}

/// Missing inptus from LLBuild
struct LLBuildMissingInputs: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildMissingInputs.self,
        name: "org.swift.diags.llbuild-missing-inputs",
        defaultBehavior: .error,
        description: {
            $0 <<< "couldn't build "
            $0 <<< { $0.output.key }
            $0 <<< " because of missing inputs: "
            $0 <<< { $0.inputs.map({ $0.key }).joined(separator: ", ") }
        }
    )

    let output: BuildKey
    let inputs: [BuildKey]
}

/// Multiple producers from LLBuild
struct LLBuildMultipleProducers: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildMultipleProducers.self,
        name: "org.swift.diags.llbuild-multiple-producers",
        defaultBehavior: .error,
        description: {
            $0 <<< "couldn't build "
            $0 <<< { $0.output.key }
            $0 <<< " because of multiple producers: "
            $0 <<< { $0.commands.map({ $0.description }).joined(separator: ", ") }
        }
    )

    let output: BuildKey
    let commands: [SPMLLBuild.Command]
}

/// Command error from LLBuild
struct LLBuildCommandError: DiagnosticData {
    static let id = DiagnosticID(
        type: LLBuildCommandError.self,
        name: "org.swift.diags.llbuild-command-error",
        defaultBehavior: .error,
        description: {
            $0 <<< "command "
            $0 <<< { $0.command.description }
            $0 <<< " failed: "
            $0 <<< { $0.message }
        }
    )

    let command: SPMLLBuild.Command
    let message: String
}

/// Swift Compiler output parsing error
struct SwiftCompilerOutputParsingError: DiagnosticData {
    static let id = DiagnosticID(
        type: SwiftCompilerOutputParsingError.self,
        name: "org.swift.diags.swift-compiler-output-parsing-error",
        defaultBehavior: .error,
        description: {
            $0 <<< "failed parsing the Swift compiler output: "
            $0 <<< { $0.message }
        }
    )

    let message: String
}

extension SPMLLBuild.Diagnostic: DiagnosticDataConvertible {
    public var diagnosticData: DiagnosticData {
        switch kind {
        case .error: return LLBuildErrorDiagnostic(message: message)
        case .warning: return LLBuildWarningDiagnostic(message: message)
        case .note: return LLBuildNoteDiagnostic(message: message)
        }
    }
}

class CustomLLBuildCommand: ExternalCommand {
    let ctx: BuildExecutionContext

    required init(_ ctx: BuildExecutionContext) {
        self.ctx = ctx
    }

    func getSignature(_ command: SPMLLBuild.Command) -> [UInt8] {
        return []
    }

    func execute(_ command: SPMLLBuild.Command) -> Bool {
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

    private func execute(with tool: ToolProtocol) throws {
        assert(tool is TestDiscoveryTool, "Unexpected tool \(tool)")

        let index = ctx.buildParameters.indexStore
        let api = try ctx.indexStoreAPI.dematerialize()
        let store = try IndexStore.open(store: index, api: api)

        // FIXME: We can speed this up by having one llbuild command per object file.
        let tests = try tool.inputs.flatMap {
            try store.listTests(inObjectFile: AbsolutePath($0))
        }

        let outputs = tool.outputs.compactMap{ try? AbsolutePath(validating: $0) }
        let testsByModule = Dictionary(grouping: tests, by: { $0.module })

        func isMainFile(_ path: AbsolutePath) -> Bool {
            return path.basename == "main.swift"
        }

        // Write one file for each test module.
        //
        // We could write everything in one file but that can easily run into type conflicts due
        // in complex packages with large number of test targets.
        for file in outputs {
            if isMainFile(file) { continue }

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
        let mainFile = outputs.first(where: isMainFile)!
        let stream = try LocalFileOutputByteStream(mainFile)

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

    override func execute(_ command: SPMLLBuild.Command) -> Bool {
        guard let tool = ctx.buildTimeCmdToolMap[command.name] else {
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

    init(_ ctx: BuildExecutionContext) {
        self.ctx = ctx
    }

    func createCommand(_ name: String) -> ExternalCommand {
        // FIXME: This should be able to dynamically look up the right command.
        switch ctx.buildTimeCmdToolMap[name] {
        case is TestDiscoveryTool:
            return TestDiscoveryCommand(ctx)
        default:
            fatalError("Unhandled command \(name)")
        }
    }
}

/// The context available during build execution.
public final class BuildExecutionContext {

    /// Mapping of command-name to its tool.
    let buildTimeCmdToolMap: [String: ToolProtocol]

    var indexStoreAPI: Result<IndexStoreAPI, AnyError> {
        indexStoreAPICache.getValue(self)
    }

    let buildParameters: BuildParameters

    public init(_ plan: BuildPlan, buildTimeCmdToolMap: [String: ToolProtocol]) {
        self.buildParameters = plan.buildParameters
        self.buildTimeCmdToolMap = buildTimeCmdToolMap
    }

    // MARK:- Private

    private var indexStoreAPICache = LazyCache(createIndexStoreAPI)
    private func createIndexStoreAPI() -> Result<IndexStoreAPI, AnyError> {
        Result {
            let ext = buildParameters.triple.dynamicLibraryExtension
            let indexStoreLib = buildParameters.toolchain.toolchainLibDir.appending(component: "libIndexStore" + ext)
            return try IndexStoreAPI(dylib: indexStoreLib)
        }
    }
}

private let newLineByte: UInt8 = 10
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
    /// Target name keyed by llbuild command name.
    private let targetNames: [String: String]

    let buildExecutionContext: BuildExecutionContext

    public init(
        bctx: BuildExecutionContext,
        plan: BuildPlan,
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

        let buildConfig = plan.buildParameters.configuration.dirname

        targetNames = Dictionary(uniqueKeysWithValues: plan.targetMap.map({ (target, description) in
            return (target.getCommandName(config: buildConfig), target.name)
        }))

        swiftParsers = Dictionary(uniqueKeysWithValues: plan.targetMap.compactMap({ (target, description) in
            guard case .swift = description else { return nil }
            let parser = SwiftCompilerOutputParser(targetName: target.name, delegate: self)
            return (target.getCommandName(config: buildConfig), parser)
        }))
    }

    public var fs: SPMLLBuild.FileSystem? {
        return nil
    }

    public func lookupTool(_ name: String) -> Tool? {
        switch name {
        case TestDiscoveryTool.name:
            return InProcessTool(buildExecutionContext)
        default:
            return nil
        }
    }

    public func hadCommandFailure() {
        onCommmandFailure?()
    }

    public func handleDiagnostic(_ diagnostic: SPMLLBuild.Diagnostic) {
        diagnostics.emit(diagnostic)
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
            let targetName = self.targetNames[command.name]
            self.taskTracker.commandFinished(command, result: result, targetName: targetName)
            self.updateProgress()
        }
    }

    public func commandHadError(_ command: SPMLLBuild.Command, message: String) {
        diagnostics.emit(data: LLBuildCommandErrorDiagnostic(message: message))
    }

    public func commandHadNote(_ command: SPMLLBuild.Command, message: String) {
        diagnostics.emit(data: LLBuildCommandNoteDiagnostic(message: message))
    }

    public func commandHadWarning(_ command: SPMLLBuild.Command, message: String) {
        diagnostics.emit(data: LLBuildCommandWarningDiagnostic(message: message))
    }

    public func commandCannotBuildOutputDueToMissingInputs(
        _ command: SPMLLBuild.Command,
        output: BuildKey,
        inputs: [BuildKey]
    ) {
        diagnostics.emit(data: LLBuildMissingInputs(output: output, inputs: inputs))
    }

    public func cannotBuildNodeDueToMultipleProducers(output: BuildKey, commands: [SPMLLBuild.Command]) {
        diagnostics.emit(data: LLBuildMultipleProducers(output: output, commands: commands))
    }

    public func commandProcessStarted(_ command: SPMLLBuild.Command, process: ProcessHandle) {
    }

    public func commandProcessHadError(_ command: SPMLLBuild.Command, process: ProcessHandle, message: String) {
        diagnostics.emit(data: LLBuildCommandError(command: command, message: message))
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
        diagnostics.emit(data: LLBuildCycleErrorDiagnostic(rules: rules))
    }

    public func shouldResolveCycle(rules: [BuildKey], candidate: BuildKey, action: CycleAction) -> Bool {
        return false
    }

    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage) {
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

    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics.emit(data: SwiftCompilerOutputParsingError(message: message))
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
