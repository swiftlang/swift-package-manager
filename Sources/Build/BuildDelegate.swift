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
import POSIX

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

    public init(
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

        let buildConfig = plan.buildParameters.configuration.dirname
        swiftParsers = Dictionary(uniqueKeysWithValues: plan.targetMap.compactMap({ (target, description) in
            guard case .swift = description else { return nil }
            return (target.getCommandName(config: buildConfig), SwiftCompilerOutputParser(delegate: self))
        }))
    }

    public var fs: SPMLLBuild.FileSystem? {
        return nil
    }

    public func lookupTool(_ name: String) -> Tool? {
        return nil
    }

    public func hadCommandFailure() {
        onCommmandFailure?()
    }

    public func handleDiagnostic(_ diagnostic: SPMLLBuild.Diagnostic) {
        diagnostics.emit(diagnostic)
    }

    public func commandStatusChanged(_ command: SPMLLBuild.Command, kind: CommandStatusKind) {
    }

    public func commandPreparing(_ command: SPMLLBuild.Command) {
    }

    public func commandStarted(_ command: SPMLLBuild.Command) {
        guard command.shouldShowStatus else { return }
        guard !swiftParsers.keys.contains(command.name) else { return }

        queue.sync {
            if isVerbose {
                outputStream <<< command.verboseDescription <<< "\n"
                outputStream.flush()
            } else {
                taskTracker.commandStarted(command)
                updateProgress()
            }
        }
    }

    public func shouldCommandStart(_ command: SPMLLBuild.Command) -> Bool {
        return true
    }

    public func commandFinished(_ command: SPMLLBuild.Command, result: CommandResult) {
        guard command.shouldShowStatus else { return }
        guard !swiftParsers.keys.contains(command.name) else { return }
        guard !isVerbose else { return }

        queue.sync {
            taskTracker.commandFinished(command, result: result)
            updateProgress()
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
            progressAnimation.clear()
            outputStream <<< data
            outputStream.flush()
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

    func swiftCompilerDidOutputMessage(_ message: SwiftCompilerMessage) {
        queue.sync {
            if isVerbose {
                if let text = message.verboseProgressText {
                    outputStream <<< text <<< "\n"
                    outputStream.flush()
                }
            } else {
                taskTracker.swiftCompilerDidOuputMessage(message)
                updateProgress()
            }

            if let output = message.standardOutput {
                if !isVerbose {
                    progressAnimation.clear()
                }

                outputStream <<< output
                outputStream.flush()
            }
        }
    }

    func swiftCompilerOutputParserDidFail(withError error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics.emit(data: SwiftCompilerOutputParsingError(message: message))
        onCommmandFailure?()
    }

    private func updateProgress() {
        if let progressText = taskTracker.latestRunningText {
            progressAnimation.update(
                step: taskTracker.finishedCount,
                total: taskTracker.totalCount,
                text: progressText)
        }
    }
}

/// Tracks tasks based on command status and swift compiler output.
fileprivate struct CommandTaskTracker {
    private struct Task {
        let identifier: String
        let text: String
    }

    private var tasks: [Task] = []
    private(set) var finishedCount = 0
    private(set) var totalCount = 0

    /// The last task text before the task list was emptied.
    private var lastText: String?
    
    var latestRunningText: String? {
        return tasks.last?.text ?? lastText
    }
    
    mutating func commandStarted(_ command: SPMLLBuild.Command) {
        addTask(identifier: command.name, text: command.description)
        totalCount += 1
    }
    
    mutating func commandFinished(_ command: SPMLLBuild.Command, result: CommandResult) {
        removeTask(identifier: command.name)

        switch result {
        case .succeeded:
            finishedCount += 1
        case .cancelled, .failed, .skipped:
            break
        }
    }
    
    mutating func swiftCompilerDidOuputMessage(_ message: SwiftCompilerMessage) {
        switch message.kind {
        case .began(let info):
            if let text = message.progressText {
                addTask(identifier: info.pid.description, text: text)
            }

            totalCount += 1
        case .finished(let info):
            removeTask(identifier: info.pid.description)
            finishedCount += 1
        case .signalled(let info):
            removeTask(identifier: info.pid.description)
        case .skipped:
            break
        }
    }
    
    private mutating func addTask(identifier: String, text: String) {
        tasks.append(Task(identifier: identifier, text: text))
    }
    
    private mutating func removeTask(identifier: String) {
        if let index = tasks.index(where: { $0.identifier == identifier }) {
            if tasks.count == 1 {
                lastText = tasks[0].text
            }

            tasks.remove(at: index)
        }
    }
}

extension SwiftCompilerMessage {
    fileprivate var progressText: String? {
        if case .began(let info) = kind {
            switch name {
            case "compile":
                if let sourceFile = info.inputs.first {
                    return generateProgressText(prefix: "Compiling", file: sourceFile)
                }
            case "link":
                if let imageFile = info.outputs.first(where: { $0.type == "image" })?.path {
                    return generateProgressText(prefix: "Linking", file: imageFile)
                }
            case "merge-module":
                if let moduleFile = info.outputs.first(where: { $0.type == "swiftmodule" })?.path {
                    return generateProgressText(prefix: "Merging module", file: moduleFile)
                }
            case "generate-dsym":
                if let dSYMFile = info.outputs.first(where: { $0.type == "dSYM" })?.path {
                    return generateProgressText(prefix: "Generating dSYM", file: dSYMFile)
                }
            case "generate-pch":
                if let pchFile = info.outputs.first(where: { $0.type == "pch" })?.path {
                    return generateProgressText(prefix: "Generating PCH", file: pchFile)
                }
            default:
                break
            }
        }

        return nil
    }

    fileprivate var verboseProgressText: String? {
        if case .began(let info) = kind {
            return ([info.commandExecutable] + info.commandArguments).joined(separator: " ")
        } else {
            return nil
        }
    }

    fileprivate var standardOutput: String? {
        switch kind {
        case .finished(let info),
             .signalled(let info):
            return info.output
        default:
            return nil
        }
    }

    private func generateProgressText(prefix: String, file: String) -> String {
        let relativePath = AbsolutePath(file).relative(to: AbsolutePath(getcwd()))
        return "\(prefix) \(relativePath)"
    }
}
