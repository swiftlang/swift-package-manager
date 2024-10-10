//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SwiftPMInternal)
import Basics
import Dispatch
import Foundation
import LLBuildManifest
import PackageModel
import SPMBuildCore
import SPMLLBuild

import protocol TSCBasic.OutputByteStream
import struct TSCBasic.RegEx
import class TSCBasic.ThreadSafeOutputByteStream

import class TSCUtility.IndexStoreAPI

#if canImport(llbuildSwift)
typealias LLBuildBuildSystemDelegate = llbuildSwift.BuildSystemDelegate
#else
typealias LLBuildBuildSystemDelegate = llbuild.BuildSystemDelegate
#endif

private final class InProcessTool: Tool {
    let context: BuildExecutionContext
    let type: CustomLLBuildCommand.Type

    init(_ context: BuildExecutionContext, type: CustomLLBuildCommand.Type) {
        self.context = context
        self.type = type
    }

    func createCommand(_: String) -> ExternalCommand? {
        type.init(self.context)
    }
}

/// A provider of advice about build errors.
public protocol BuildErrorAdviceProvider {
    /// Invoked after a command fails and an error message is detected in the output. Should return a string containing
    /// advice or additional information, if any, based on the build plan.
    func provideBuildErrorAdvice(for target: String, command: String, message: String) -> String?
}

/// The context available during build execution.
public final class BuildExecutionContext {
    /// Build parameters for products.
    let productsBuildParameters: BuildParameters

    /// Build parameters for build tools.
    let toolsBuildParameters: BuildParameters

    /// The build description.
    ///
    /// This is optional because we might not have a valid build description when performing the
    /// build for PackageStructure target.
    let buildDescription: BuildDescription?

    /// The package structure delegate.
    let packageStructureDelegate: PackageStructureDelegate

    /// Optional provider of build error resolution advice.
    let buildErrorAdviceProvider: BuildErrorAdviceProvider?

    let fileSystem: Basics.FileSystem

    let observabilityScope: ObservabilityScope

    public init(
        productsBuildParameters: BuildParameters,
        toolsBuildParameters: BuildParameters,
        buildDescription: BuildDescription? = nil,
        fileSystem: Basics.FileSystem,
        observabilityScope: ObservabilityScope,
        packageStructureDelegate: PackageStructureDelegate,
        buildErrorAdviceProvider: BuildErrorAdviceProvider? = nil
    ) {
        self.productsBuildParameters = productsBuildParameters
        self.toolsBuildParameters = toolsBuildParameters
        self.buildDescription = buildDescription
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
        self.packageStructureDelegate = packageStructureDelegate
        self.buildErrorAdviceProvider = buildErrorAdviceProvider
    }

    // MARK: - Private

    private var indexStoreAPICache = ThreadSafeBox<Result<IndexStoreAPI, Error>>()

    /// Reference to the index store API.
    var indexStoreAPI: Result<IndexStoreAPI, Error> {
        self.indexStoreAPICache.memoize {
            do {
                #if os(Windows)
                // The library's runtime component is in the `bin` directory on
                // Windows rather than the `lib` directory as on Unix.  The `lib`
                // directory contains the import library (and possibly static
                // archives) which are used for linking.  The runtime component is
                // not (necessarily) part of the SDK distributions.
                //
                // NOTE: the library name here `libIndexStore.dll` is technically
                // incorrect as per the Windows naming convention.  However, the
                // library is currently installed as `libIndexStore.dll` rather than
                // `IndexStore.dll`.  In the future, this may require a fallback
                // search, preferring `IndexStore.dll` over `libIndexStore.dll`.
                let indexStoreLib = self.toolsBuildParameters.toolchain.swiftCompilerPath
                    .parentDirectory
                    .appending("libIndexStore.dll")
                #else
                let ext = self.toolsBuildParameters.triple.dynamicLibraryExtension
                let indexStoreLib = try toolsBuildParameters.toolchain.toolchainLibDir
                    .appending("libIndexStore" + ext)
                #endif
                return try .success(IndexStoreAPI(dylib: TSCAbsolutePath(indexStoreLib)))
            } catch {
                return .failure(error)
            }
        }
    }
}

public protocol PackageStructureDelegate {
    func packageStructureChanged() async -> Bool
}

/// Convenient llbuild build system delegate implementation
final class LLBuildProgressTracker: LLBuildBuildSystemDelegate, SwiftCompilerOutputParserDelegate {
    private let progressAnimation: ProgressAnimationProtocol
    private let logLevel: Basics.Diagnostic.Severity
    private weak var delegate: SPMBuildCore.BuildSystemDelegate?
    private let buildSystem: SPMBuildCore.BuildSystem
    private let queue = DispatchQueue(label: "org.swift.swiftpm.build-delegate")
    private var taskTracker: CommandTaskTracker
    private var errorMessagesByTarget: [String: [String]] = [:]
    private let observabilityScope: ObservabilityScope
    private var cancelled: Bool = false

    /// Swift parsers keyed by llbuild command name.
    private var swiftParsers: [String: SwiftCompilerOutputParser] = [:]

    /// Buffer to accumulate non-swift output until command is finished
    private var nonSwiftMessageBuffers: [String: [UInt8]] = [:]

    /// The build execution context.
    private let buildExecutionContext: BuildExecutionContext

    init(
        buildSystem: SPMBuildCore.BuildSystem,
        buildExecutionContext: BuildExecutionContext,
        progressAnimation: ProgressAnimationProtocol,
        logLevel: Basics.Diagnostic.Severity,
        observabilityScope: ObservabilityScope,
        delegate: SPMBuildCore.BuildSystemDelegate?
    ) {
        self.buildSystem = buildSystem
        self.buildExecutionContext = buildExecutionContext
        self.progressAnimation = progressAnimation
        self.taskTracker = .init(progressAnimation: progressAnimation)
        self.logLevel = logLevel
        self.observabilityScope = observabilityScope
        self.delegate = delegate

        let swiftParsers = buildExecutionContext.buildDescription?.swiftCommands.mapValues { tool in
            SwiftCompilerOutputParser(targetName: tool.moduleName, delegate: self)
        } ?? [:]
        self.swiftParsers = swiftParsers
    }

    // MARK: llbuildSwift.BuildSystemDelegate

    var fs: SPMLLBuild.FileSystem? {
        nil
    }

    func lookupTool(_ name: String) -> Tool? {
        switch name {
        case TestDiscoveryTool.name:
            InProcessTool(self.buildExecutionContext, type: TestDiscoveryCommand.self)
        case TestEntryPointTool.name:
            InProcessTool(self.buildExecutionContext, type: TestEntryPointCommand.self)
        case PackageStructureTool.name:
            InProcessTool(self.buildExecutionContext, type: PackageStructureCommand.self)
        case CopyTool.name:
            InProcessTool(self.buildExecutionContext, type: CopyCommand.self)
        case WriteAuxiliaryFile.name:
            InProcessTool(self.buildExecutionContext, type: WriteAuxiliaryFileCommand.self)
        default:
            nil
        }
    }

    func hadCommandFailure() {
        do {
            try self.buildSystem.cancel(deadline: .now())
        } catch {
            self.observabilityScope.emit(error: "failed to cancel the build: \(error)")
        }
        self.delegate?.buildSystemDidCancel(self.buildSystem)
    }

    func handleDiagnostic(_ diagnostic: SPMLLBuild.Diagnostic) {
        switch diagnostic.kind {
        case .note:
            self.observabilityScope.emit(info: diagnostic.message)
        case .warning:
            self.observabilityScope.emit(warning: diagnostic.message)
        case .error:
            self.observabilityScope.emit(error: diagnostic.message)
        @unknown default:
            self.observabilityScope.emit(info: diagnostic.message)
        }
    }

    func commandStatusChanged(_ command: SPMLLBuild.Command, kind: CommandStatusKind) {
        guard command.shouldShowStatus else { return }
        let targetName = self.swiftParsers[command.name]?.targetName
        let now = ContinuousClock.now

        queue.async {
            self.taskTracker.commandStatusChanged(
                command,
                kind: kind,
                targetName: targetName,
                time: now)
        }
    }

    func commandPreparing(_ command: SPMLLBuild.Command) {
        self.queue.async {
            self.delegate?.buildSystem(self.buildSystem, willStartCommand: BuildSystemCommand(command))
        }
    }

    func commandStarted(_ command: SPMLLBuild.Command) {
        guard command.shouldShowStatus else { return }
        let targetName = self.swiftParsers[command.name]?.targetName
        let now = ContinuousClock.now

        self.queue.async {
            self.delegate?.buildSystem(self.buildSystem, didStartCommand: BuildSystemCommand(command))

            if self.logLevel.isVerbose {
                self.progressAnimation.interleave("\(command.verboseDescription)\n")
            }

            self.taskTracker.commandStarted(
                command,
                targetName: targetName,
                time: now)
        }
    }

    func shouldCommandStart(_: SPMLLBuild.Command) -> Bool {
        true
    }

    func commandFinished(_ command: SPMLLBuild.Command, result: CommandResult) {
        guard command.shouldShowStatus else { return }
        let targetName = self.swiftParsers[command.name]?.targetName
        let now = ContinuousClock.now

        self.queue.async {
            if result == .cancelled {
                self.cancelled = true
                self.delegate?.buildSystemDidCancel(self.buildSystem)
            }

            self.delegate?.buildSystem(self.buildSystem, didFinishCommand: BuildSystemCommand(command))

            self.taskTracker.commandFinished(command, result: result, targetName: targetName, time: now)
        }
    }

    func commandHadError(_ command: SPMLLBuild.Command, message: String) {
        self.observabilityScope.emit(error: message)
    }

    func commandHadNote(_ command: SPMLLBuild.Command, message: String) {
        self.observabilityScope.emit(info: message)
    }

    func commandHadWarning(_ command: SPMLLBuild.Command, message: String) {
        self.observabilityScope.emit(warning: message)
    }

    func commandCannotBuildOutputDueToMissingInputs(
        _ command: SPMLLBuild.Command,
        output: BuildKey,
        inputs: [BuildKey]
    ) {
        self.observabilityScope.emit(.missingInputs(output: output, inputs: inputs))
    }

    func cannotBuildNodeDueToMultipleProducers(output: BuildKey, commands: [SPMLLBuild.Command]) {
        self.observabilityScope.emit(.multipleProducers(output: output, commands: commands))
    }

    func commandProcessStarted(_ command: SPMLLBuild.Command, process: ProcessHandle) {}

    func commandProcessHadError(_ command: SPMLLBuild.Command, process: ProcessHandle, message: String) {
        self.observabilityScope.emit(.commandError(command: command, message: message))
    }

    func commandProcessHadOutput(_ command: SPMLLBuild.Command, process: ProcessHandle, data: [UInt8]) {
        guard command.shouldShowStatus else { return }

        if let swiftParser = swiftParsers[command.name] {
            swiftParser.parse(bytes: data)
        } else {
            self.queue.async {
                self.nonSwiftMessageBuffers[command.name, default: []] += data
            }
        }
    }

    func commandProcessFinished(
        _ command: SPMLLBuild.Command,
        process: ProcessHandle,
        result: CommandExtendedResult
    ) {
        // FIXME: This should really happen at the command-level and is just a stopgap measure.
        let shouldFilterOutput = !self.logLevel.isVerbose && command.verboseDescription.hasPrefix("codesign ") && result
            .result != .failed
        self.queue.async {
            if let buffer = self.nonSwiftMessageBuffers[command.name], !shouldFilterOutput {
                self.progressAnimation.interleave(buffer)
                self.nonSwiftMessageBuffers[command.name] = nil
            }
        }

        switch result.result {
        case .cancelled:
            self.cancelled = true
            self.delegate?.buildSystemDidCancel(self.buildSystem)
        case .failed:
            // The command failed, so we queue up an asynchronous task to see if we have any error messages from the
            // target to provide advice about.
            self.queue.async {
                guard let target = self.swiftParsers[command.name]?.targetName else { return }
                guard let errorMessages = self.errorMessagesByTarget[target] else { return }
                for errorMessage in errorMessages {
                    // Emit any advice that's provided for each error message.
                    if let adviceMessage = self.buildExecutionContext.buildErrorAdviceProvider?.provideBuildErrorAdvice(
                        for: target,
                        command: command.name,
                        message: errorMessage
                    ) {
                        self.progressAnimation.interleave("note: \(adviceMessage)\n")
                    }
                }
            }
        case .succeeded, .skipped:
            break
        @unknown default:
            break
        }
    }

    func cycleDetected(rules: [BuildKey]) {
        self.observabilityScope.emit(.cycleError(rules: rules))

        self.queue.async {
            self.delegate?.buildSystemDidDetectCycleInRules(self.buildSystem)
        }
    }

    func shouldResolveCycle(rules: [BuildKey], candidate: BuildKey, action: CycleAction) -> Bool {
        false
    }

    /// Invoked right before running an action taken before building.
    func preparationStepStarted(_ name: String) {
        let now = ContinuousClock.now
        self.queue.async {
            self.taskTracker.buildPreparationStepStarted(name, time: now)
        }
    }

    /// Invoked when an action taken before building emits output.
    /// when verboseOnly is set to true, the output will only be printed in verbose logging mode
    func preparationStepHadOutput(_ name: String, output: String, verboseOnly: Bool) {
        if !verboseOnly || self.logLevel.isVerbose {
            self.queue.async {
                self.progressAnimation.interleave("\(output.spm_chomp())\n")
            }
        }
    }

    /// Invoked right after running an action taken before building. The result
    /// indicates whether the action succeeded, failed, or was cancelled.
    func preparationStepFinished(_ name: String, result: CommandResult) {
        let now = ContinuousClock.now
        self.queue.async {
            self.taskTracker.buildPreparationStepFinished(name, time: now)
        }
    }

    // MARK: SwiftCompilerOutputParserDelegate
    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didParse message: SwiftCompilerMessage) {
        let now = ContinuousClock.now
        self.queue.async {
            if self.logLevel.isVerbose, let text = message.verboseProgressText {
                self.progressAnimation.interleave("\(text)\n")
            }

            if let output = message.standardOutput {
                self.progressAnimation.interleave(output)

                // next we want to try and scoop out any errors from the output (if reasonable size, otherwise this
                // will be very slow), so they can later be passed to the advice provider in case of failure.
                if output.utf8.count < 1024 * 10 {
                    let regex = try! RegEx(pattern: #".*(error:[^\n]*)\n.*"#, options: .dotMatchesLineSeparators)
                    for match in regex.matchGroups(in: output) {
                        self.errorMessagesByTarget[parser.targetName] = (
                            self.errorMessagesByTarget[parser.targetName] ?? []
                        ) + [match[0]]
                    }
                }
            }

            self.taskTracker.swiftCompilerDidOutputMessage(
                message,
                targetName: parser.targetName,
                time: now)
        }
    }

    func swiftCompilerOutputParser(_ parser: SwiftCompilerOutputParser, didFailWith error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        self.observabilityScope.emit(.swiftCompilerOutputParsingError(message))
    }

    func buildStart(
        configuration: BuildConfiguration,
        action: String
    ) { }

    func buildComplete(
        success: Bool,
        duration: DispatchTimeInterval,
        action: String,
        subsetDescriptor: String? = nil
    ) {
        let subsetString = if let subsetDescriptor {
            "of \(subsetDescriptor) "
        } else {
            ""
        }

        self.queue.sync {
            let result = !success ? "failed" :
                self.cancelled ? "cancelled" : "complete" 
            self.progressAnimation.complete("\(action) \(subsetString)\(result)!")
        }
    }
}

/// Tracks tasks based on command status and swift compiler output.
private struct CommandTaskTracker {
    var progressAnimation: any ProgressAnimationProtocol
    var swiftTaskProgressTexts: [Int: String]

    init(progressAnimation: ProgressAnimationProtocol) {
        self.progressAnimation = progressAnimation
        self.swiftTaskProgressTexts = [:]
    }

    mutating func commandStatusChanged(
        _ command: SPMLLBuild.Command,
        kind: CommandStatusKind,
        targetName: String?,
        time: ContinuousClock.Instant
    ) {
        let event: ProgressTaskState
        switch kind {
        case .isScanning: event = .discovered
        case .isUpToDate: event = .completed(.skipped)
        case .isComplete: event = .completed(.succeeded)
        @unknown default:
            assertionFailure("unhandled command status kind \(kind) for command \(command)")
            return
        }
        let name = self.progressText(of: command, targetName: targetName)
        self.progressAnimation.update(
            id: command.unstableId,
            name: name,
            event: event,
            at: time)
    }

    mutating func commandStarted(
        _ command: SPMLLBuild.Command,
        targetName: String?,
        time: ContinuousClock.Instant
    ) {
        let name = self.progressText(of: command, targetName: targetName)
        self.progressAnimation.update(
            id: command.unstableId,
            name: name,
            event: .started,
            at: time)
    }

    mutating func commandFinished(
        _ command: SPMLLBuild.Command,
        result: CommandResult,
        targetName: String?,
        time: ContinuousClock.Instant
    ) {
        let name = self.progressText(of: command, targetName: targetName)
        let event: ProgressTaskCompletion
        switch result {
        case .succeeded: event = .succeeded
        case .failed: event = .failed
        case .cancelled: event = .cancelled
        case .skipped: event = .skipped
        @unknown default:
            assertionFailure("unhandled command result \(result) for command \(command)")
            return
        }
        self.progressAnimation.update(
            id: command.unstableId,
            name: name,
            event: .completed(event),
            at: time)
    }

    mutating func swiftCompilerDidOutputMessage(
        _ message: SwiftCompilerMessage,
        targetName: String,
        time: ContinuousClock.Instant
    ) {
        switch message.kind {
        case .began(let info):
            if let task = self.progressText(of: message, targetName: targetName) {
                self.swiftTaskProgressTexts[info.pid] = task
//                self.progressAnimation.update(id: info.pid, name: task, event: .discovered, at: time)
//                self.progressAnimation.update(id: info.pid, name: task, event: .started, at: time)
            }

        case .finished(let info):
            if let task = self.swiftTaskProgressTexts[info.pid] {
                swiftTaskProgressTexts[info.pid] = nil
//                self.progressAnimation.update(id: info.pid, name: task, event: .completed(.succeeded), at: time)
            }

        case .unparsableOutput, .abnormal, .signalled, .skipped:
            break
        }
    }

    private func progressText(of command: SPMLLBuild.Command, targetName: String?) -> String {
        // Transforms descriptions like "Linking ./.build/x86_64-apple-macosx/debug/foo" into "Linking foo".
        if let firstSpaceIndex = command.description.firstIndex(of: " "),
           let lastDirectorySeparatorIndex = command.description.lastIndex(of: "/")
        {
            let action = command.description[..<firstSpaceIndex]
            let fileNameStartIndex = command.description.index(after: lastDirectorySeparatorIndex)
            let fileName = command.description[fileNameStartIndex...]

            if let targetName {
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
                    let sourceFilePath = try! AbsolutePath(validating: sourceFile)
                    return "Compiling \(targetName) \(sourceFilePath.components.last!)"
                }
            case "link":
                return "Linking \(targetName)"
            case "merge-module":
                return "Merging module \(targetName)"
            case "emit-module":
                return "Emitting module \(targetName)"
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

    mutating func buildPreparationStepStarted(
        _ name: String,
        time: ContinuousClock.Instant
    ) {
        self.progressAnimation.update(
            id: name.hash,
            name: name,
            event: .discovered,
            at: time)
        self.progressAnimation.update(
            id: name.hash,
            name: name,
            event: .started,
            at: time)
    }

    mutating func buildPreparationStepFinished(
        _ name: String,
        time: ContinuousClock.Instant
    ) {
        self.progressAnimation.update(
            id: name.hash,
            name: name,
            event: .completed(.succeeded),
            at: time)
    }
}

extension SwiftCompilerMessage {
    fileprivate var verboseProgressText: String? {
        switch kind {
        case .began(let info):
            ([info.commandExecutable] + info.commandArguments).joined(separator: " ")
        case .skipped, .finished, .abnormal, .signalled, .unparsableOutput:
            nil
        }
    }

    fileprivate var standardOutput: String? {
        switch kind {
        case .finished(let info),
             .abnormal(let info),
             .signalled(let info):
            info.output
        case .unparsableOutput(let output):
            output
        case .skipped, .began:
            nil
        }
    }
}

extension Basics.Diagnostic {
    fileprivate static func cycleError(rules: [BuildKey]) -> Self {
        .error("build cycle detected: " + rules.map(\.key).joined(separator: ", "))
    }

    fileprivate static func missingInputs(output: BuildKey, inputs: [BuildKey]) -> Self {
        let missingInputs = inputs.map(\.key).joined(separator: ", ")
        return .error("couldn't build \(output.key) because of missing inputs: \(missingInputs)")
    }

    fileprivate static func multipleProducers(output: BuildKey, commands: [SPMLLBuild.Command]) -> Self {
        let producers = commands.map(\.description).joined(separator: ", ")
        return .error("couldn't build \(output.key) because of multiple producers: \(producers)")
    }

    fileprivate static func commandError(command: SPMLLBuild.Command, message: String) -> Self {
        .error("command \(command.description) failed: \(message)")
    }

    fileprivate static func swiftCompilerOutputParsingError(_ error: String) -> Self {
        .error("failed parsing the Swift compiler output: \(error)")
    }
}

extension BuildSystemCommand {
    fileprivate init(_ command: SPMLLBuild.Command) {
        self.init(
            name: command.name,
            description: command.description,
            verboseDescription: command.verboseDescription
        )
    }
}

extension SPMLLBuild.Command {
    var unstableId: Int {
        var hasher = Hasher()
        hasher.combine(self)
        return hasher.finalize()
    }
}
