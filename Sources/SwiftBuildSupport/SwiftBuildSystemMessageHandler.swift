//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(SwiftPMInternal)
import Basics
import Foundation
@_spi(SwiftPMInternal)
import SPMBuildCore
import enum TSCUtility.Diagnostics
import SWBBuildService
import SwiftBuild
import protocol TSCBasic.OutputByteStream


/// Handler for SwiftBuildMessage events sent by the SWBBuildOperation.
public final class SwiftBuildSystemMessageHandler {
    private let observabilityScope: ObservabilityScope
    private let logLevel: Basics.Diagnostic.Severity
    private var buildState: BuildState = .init()

    let progressAnimation: ProgressAnimationProtocol
    var serializedDiagnosticPathsByTargetID: [Int: [Basics.AbsolutePath]] = [:]
    // FIXME: This eventually gets passed into the BuildResult, which expects a
    // dictionary of [String: [AbsolutePath]]. Eventually, we should refactor it
    // to accept a dictionary keyed by a unique identifier (possibly `ResolvedModule.ID`),
    // and instead use the above dictionary keyed by target ID.
    var serializedDiagnosticPathsByTargetName: [String: [Basics.AbsolutePath]] {
        serializedDiagnosticPathsByTargetID.reduce(into: [:]) { result, entry in
            if let name = buildState.targetsByID[entry.key]?.targetName {
                result[name, default: []].append(contentsOf: entry.value)
            }
        }
    }

    /// Tracks the task IDs for failed tasks.
    private var failedTasks: [Int] = []
    /// Tracks the tasks by their signature for which we have already emitted output.
    private var tasksEmitted: EmittedTasks = .init()

    public init(
        observabilityScope: ObservabilityScope,
        outputStream: OutputByteStream,
        logLevel: Basics.Diagnostic.Severity
    )
    {
        self.observabilityScope = observabilityScope
        self.logLevel = logLevel
        self.progressAnimation = ProgressAnimation.ninja(
            stream: outputStream,
            verbose: self.logLevel.isVerbose
        )
    }

    private func emitInfoAsDiagnostic(info: SwiftBuildMessage.DiagnosticInfo) {
        let fixItsDescription = if info.fixIts.hasContent {
            ": " + info.fixIts.map { String(describing: $0) }.joined(separator: ", ")
        } else {
            ""
        }
        let message = if let locationDescription = info.location.userDescription {
            "\(locationDescription) \(info.message)\(fixItsDescription)"
        } else {
            "\(info.message)\(fixItsDescription)"
        }
        let severity: Diagnostic.Severity = switch info.kind {
        case .error: .error
        case .warning: .warning
        case .note: .info
        case .remark: .debug
        }
        self.observabilityScope.emit(severity: severity, message: "\(message)\n")

        for childDiagnostic in info.childDiagnostics {
            emitInfoAsDiagnostic(info: childDiagnostic)
        }
    }

    private func emitDiagnosticCompilerOutput(_ info: SwiftBuildMessage.TaskStartedInfo) {
        // Don't redundantly emit task output.
        guard !self.tasksEmitted.contains(info.taskSignature) else {
            return
        }
        // Assure we have a data buffer to decode.
        guard let buffer = buildState.dataBuffer(for: info) else {
            return
        }

        // Decode the buffer to a string
        let decodedOutput = String(decoding: buffer, as: UTF8.self)

        // Emit message.
        observabilityScope.print(decodedOutput, verbose: self.logLevel.isVerbose)

        // Record that we've emitted the output for a given task signature.
        self.tasksEmitted.insert(info)
    }

    private func handleTaskOutput(
        _ info: SwiftBuildMessage.TaskCompleteInfo,
        _ startedInfo: SwiftBuildMessage.TaskStartedInfo,
        _ enableTaskBacktraces: Bool
    ) throws {
        if info.result != .success {
            let diagnostics = self.buildState.diagnostics(for: info)
            if diagnostics.isEmpty {
                // Handle diagnostic via textual compiler output.
                emitFailedTaskOutput(info, startedInfo)
            } else {
                // Handle diagnostic via diagnostic info struct.
                diagnostics.forEach({ emitInfoAsDiagnostic(info: $0) })
            }
        } else if let data = buildState.dataBuffer(for: startedInfo), !tasksEmitted.contains(startedInfo.taskSignature) {
            let decodedOutput = String(decoding: data, as: UTF8.self)
            if !decodedOutput.isEmpty {
                observabilityScope.emit(info: decodedOutput)
            }
        }

        // Handle task backtraces, if applicable.
        if enableTaskBacktraces {
            if let id = SWBBuildOperationBacktraceFrame.Identifier(taskSignatureData: Data(startedInfo.taskSignature.utf8)),
               let backtrace = SWBTaskBacktrace(from: id, collectedFrames: buildState.collectedBacktraceFrames) {
                let formattedBacktrace = backtrace.renderTextualRepresentation()
                if !formattedBacktrace.isEmpty {
                    self.observabilityScope.emit(info: "Task backtrace:\n\(formattedBacktrace)")
                }
            }
        }
    }

    private func emitFailedTaskOutput(
        _ info: SwiftBuildMessage.TaskCompleteInfo,
        _ startedInfo: SwiftBuildMessage.TaskStartedInfo
    ) {
        // Assure that the task has failed.
        guard info.result != .success else {
            return
        }
        // Don't redundantly emit task output.
        guard !tasksEmitted.contains(startedInfo.taskSignature) else {
            return
        }

        // Track failed tasks.
        self.failedTasks.append(info.taskID)

        // Check for existing diagnostics with matching taskID/taskSignature.
        // If we've captured the compiler output with formatted diagnostics keyed by
        // this task's signature, emit them.
        // Note that this is a workaround instead of emitting directly from a `DiagnosticInfo`
        // message, as here we receive the formatted code snippet directly from the compiler.
        emitDiagnosticCompilerOutput(startedInfo)

        let message = "\(startedInfo.ruleInfo) failed with a nonzero exit code."
        // If we have the command line display string available, then we
        // should continue to emit this as an error. Otherwise, this doesn't
        // give enough information to the user for it to be useful so we can
        // demote it to an info-level log.
        if let cmdLineDisplayStr = startedInfo.commandLineDisplayString {
            self.observabilityScope.emit(severity: .error, message: "\(message) Command line: \(cmdLineDisplayStr)")
        } else {
            self.observabilityScope.emit(severity: .info, message: message)
        }

        // Track that we have emitted output for this task.
        tasksEmitted.insert(startedInfo)
    }

    func emitEvent(_ message: SwiftBuild.SwiftBuildMessage, _ buildSystem: SwiftBuildSystem) throws {
        guard !self.logLevel.isQuiet else { return }
        switch message {
        case .buildCompleted(let info):
            progressAnimation.complete(success: info.result == .ok)
            if info.result == .cancelled {
                buildSystem.delegate?.buildSystemDidCancel(buildSystem)
            } else {
                buildSystem.delegate?.buildSystem(buildSystem, didFinishWithResult: info.result == .ok)
            }
        case .didUpdateProgress(let progressInfo):
            var step = Int(progressInfo.percentComplete)
            if step < 0 { step = 0 }
            let message = if let targetName = progressInfo.targetName {
                "\(targetName) \(progressInfo.message)"
            } else {
                "\(progressInfo.message)"
            }
            progressAnimation.update(step: step, total: 100, text: message)
            buildSystem.delegate?.buildSystem(buildSystem, didUpdateTaskProgress: message)
        case .diagnostic(let info):
            // If this is representative of a global/target diagnostic
            // then we can emit immediately.
            // Otherwise, defer emission of diagnostic to matching taskCompleted event.
            if info.locationContext.isGlobal || info.locationContext.isTarget {
                emitInfoAsDiagnostic(info: info)
            } else if info.appendToOutputStream {
                buildState.appendDiagnostic(info)
            }
        case .output(let info):
            // Append to buffer-per-task storage
            buildState.appendToBuffer(info)
        case .taskStarted(let info):
            try buildState.started(task: info)

            let targetInfo = try buildState.target(for: info)
            buildSystem.delegate?.buildSystem(buildSystem, willStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
            buildSystem.delegate?.buildSystem(buildSystem, didStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
        case .taskComplete(let info):
            let startedInfo = try buildState.completed(task: info)

            // Handler for failed tasks, if applicable.
            try handleTaskOutput(info, startedInfo, buildSystem.enableTaskBacktraces)

            let targetInfo = try buildState.target(for: startedInfo)
            buildSystem.delegate?.buildSystem(buildSystem, didFinishCommand: BuildSystemCommand(startedInfo, targetInfo: targetInfo))
            if let targetID = targetInfo?.targetID {
                try serializedDiagnosticPathsByTargetID[targetID, default: []].append(contentsOf: startedInfo.serializedDiagnosticsPaths.compactMap {
                    try Basics.AbsolutePath(validating: $0.pathString)
                })
            }
        case .targetStarted(let info):
            try buildState.started(target: info)
        case .backtraceFrame(let info):
            if buildSystem.enableTaskBacktraces {
                buildState.collectedBacktraceFrames.add(frame: info)
            }
        case .targetComplete(let info):
            _ = try buildState.completed(target: info)
        case .planningOperationStarted, .planningOperationCompleted, .reportBuildDescription, .reportPathMap, .preparedForIndex, .buildStarted, .preparationComplete, .targetUpToDate, .taskUpToDate:
            break
        case .buildDiagnostic, .targetDiagnostic, .taskDiagnostic:
            break // deprecated
        case .buildOutput, .targetOutput, .taskOutput:
            break // deprecated
        @unknown default:
            break
        }
    }
}

// MARK: SwiftBuildSystemMessageHandler.BuildState

extension SwiftBuildSystemMessageHandler {
    struct BuildState {
        internal var targetsByID: [Int: SwiftBuild.SwiftBuildMessage.TargetStartedInfo] = [:]
        private var activeTasks: [Int: SwiftBuild.SwiftBuildMessage.TaskStartedInfo] = [:]
        private var completedTasks: [Int: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo] = [:]
        private var completedTargets: [Int: SwiftBuild.SwiftBuildMessage.TargetCompleteInfo] = [:]
        private var taskDataBuffer: TaskDataBuffer = .init()
        private var diagnosticsBuffer: TaskDiagnosticBuffer = .init()
        private var taskIDToSignature: [Int: String] = [:]
        var collectedBacktraceFrames = SWBBuildOperationCollectedBacktraceFrames()

        mutating func started(task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws {
            if activeTasks[task.taskID] != nil {
                throw Diagnostics.fatalError
            }
            activeTasks[task.taskID] = task
            taskIDToSignature[task.taskID] = task.taskSignature
        }

        mutating func completed(task: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo) throws -> SwiftBuild.SwiftBuildMessage.TaskStartedInfo {
            guard let startedTaskInfo = activeTasks[task.taskID] else {
                throw Diagnostics.fatalError
            }
            if completedTasks[task.taskID] != nil {
                throw Diagnostics.fatalError
            }
            // Track completed task, remove from active tasks.
            self.completedTasks[task.taskID] = task
            self.activeTasks[task.taskID] = nil

            return startedTaskInfo
        }

        mutating func started(target: SwiftBuild.SwiftBuildMessage.TargetStartedInfo) throws {
            if targetsByID[target.targetID] != nil {
                throw Diagnostics.fatalError
            }
            targetsByID[target.targetID] = target
        }

        mutating func completed(target: SwiftBuild.SwiftBuildMessage.TargetCompleteInfo) throws -> SwiftBuild.SwiftBuildMessage.TargetStartedInfo {
            guard let targetStartedInfo = targetsByID[target.targetID] else {
                throw Diagnostics.fatalError
            }

            targetsByID[target.targetID] = nil
            completedTargets[target.targetID] = target
            return targetStartedInfo
        }

        func target(for task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws -> SwiftBuild.SwiftBuildMessage.TargetStartedInfo? {
            guard let id = task.targetID else {
                return nil
            }
            guard let target = targetsByID[id] else {
                throw Diagnostics.fatalError
            }
            return target
        }

        func taskSignature(for id: Int) -> String? {
            if let signature = taskIDToSignature[id] {
                return signature
            }
            return nil
        }

        mutating func appendToBuffer(_ info: SwiftBuildMessage.OutputInfo) {
            // Attempt to key by taskSignature; at times this may not be possible,
            // in which case we'd need to fall back to using LocationContext.
            guard let taskSignature = info.locationContext2.taskSignature else {
                // If we cannot find the task signature from the locationContext2,
                // use deprecated locationContext instead to find task signature.
                // If this fails to find an associated task signature, track
                // relevant IDs from the location context in the task buffer.
                if let taskID = info.locationContext.taskID,
                   let taskSignature = self.taskSignature(for: taskID) {
                    self.taskDataBuffer[taskSignature, default: .init()].append(info.data)
                }

                self.taskDataBuffer[info.locationContext, default: .init()].append(info.data)

                return
            }

            self.taskDataBuffer[taskSignature, default: .init()].append(info.data)
        }

        func dataBuffer(for task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) -> Data? {
            guard let data = taskDataBuffer[task.taskSignature] else {
                // Fallback to checking taskID and targetID.
                return taskDataBuffer[task]
            }

            return data
        }

        mutating func appendDiagnostic(_ info: SwiftBuildMessage.DiagnosticInfo) {
            guard let taskID = info.locationContext.taskID else {
                return
            }

            diagnosticsBuffer[taskID].append(info)
        }

        func diagnostics(for task: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo) -> [SwiftBuildMessage.DiagnosticInfo] {
            return diagnosticsBuffer[task.taskID]
        }
    }
}

// MARK: - SwiftBuildSystemMessageHandler.BuildState.TaskDataBuffer

extension SwiftBuildSystemMessageHandler.BuildState {
    /// Rich model to store data buffers for a given `SwiftBuildMessage.LocationContext` or
    /// a `SwiftBuildMessage.LocationContext2`.
    struct TaskDataBuffer {
        private var taskSignatureBuffer: [String: Data] = [:]
        private var taskIDBuffer: [Int: Data] = [:]

        subscript(key: String) -> Data? {
            self.taskSignatureBuffer[key]
        }

        subscript(key: String, default defaultValue: Data) -> Data {
            get { self.taskSignatureBuffer[key] ?? defaultValue }
            set { self.taskSignatureBuffer[key] = newValue }
        }

        subscript(key: SwiftBuildMessage.LocationContext, default defaultValue: Data) -> Data {
            get {
                // Check each ID kind and try to fetch the associated buffer.
                // If unable to get a non-nil result, then follow through to the
                // next check.
                if let taskID = key.taskID,
                   let result = self.taskIDBuffer[taskID] {
                    return result
                } else {
                    return defaultValue
                }
            }

            set {
                if let taskID = key.taskID {
                    self.taskIDBuffer[taskID] = newValue
                }
            }
        }

        subscript(key: SwiftBuildMessage.LocationContext2) -> Data? {
            get {
                if let taskSignature = key.taskSignature {
                    return self.taskSignatureBuffer[taskSignature]
                }

                return nil
            }

            set {
                if let taskSignature = key.taskSignature {
                    self.taskSignatureBuffer[taskSignature] = newValue
                }
            }
        }

        subscript(task: SwiftBuildMessage.TaskStartedInfo) -> Data? {
            get {
                guard let result = self.taskSignatureBuffer[task.taskSignature] else {
                    // Default to checking targetID and taskID.
                    if let result = self.taskIDBuffer[task.taskID] {
                        return result
                    }

                    return nil
                }

                return result
            }
        }
    }

}

// MARK: - SwiftBuildSystemMessageHandler.BuildState.

extension SwiftBuildSystemMessageHandler.BuildState {
    struct TaskDiagnosticBuffer {
        private var diagnosticSignatureBuffer: [String: [SwiftBuildMessage.DiagnosticInfo]] = [:]
        private var diagnosticIDBuffer: [Int: [SwiftBuildMessage.DiagnosticInfo]] = [:]

        subscript(key: SwiftBuildMessage.LocationContext2) -> [SwiftBuildMessage.DiagnosticInfo]? {
            guard let taskSignature = key.taskSignature else {
                return nil
            }
            return self.diagnosticSignatureBuffer[taskSignature]
        }

        subscript(key: SwiftBuildMessage.LocationContext2, default defaultValue: [SwiftBuildMessage.DiagnosticInfo]) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self[key] ?? defaultValue }
            set {
                self[key, default: defaultValue]
            }
        }

        subscript(key: SwiftBuildMessage.LocationContext) -> [SwiftBuildMessage.DiagnosticInfo]? {
            guard let taskID = key.taskID else {
                return nil
            }

            return self.diagnosticIDBuffer[taskID]
        }

        subscript(key: SwiftBuildMessage.LocationContext, default defaultValue: [SwiftBuildMessage.DiagnosticInfo]) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self[key] ?? defaultValue }
        }

        subscript(key: String) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self.diagnosticSignatureBuffer[key] ?? [] }
            set { self.diagnosticSignatureBuffer[key] = newValue }
        }

        subscript(key: Int) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self.diagnosticIDBuffer[key] ?? [] }
            set { self.diagnosticIDBuffer[key] = newValue }
        }

    }
}

// MARK: - SwiftBuildSystemMessageHandler.EmittedTasks

extension SwiftBuildSystemMessageHandler {
    struct EmittedTasks: Collection {
        public typealias Index = Set<TaskInfo>.Index
        public typealias Element = Set<TaskInfo>.Element
        var startIndex: Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index {
            self.storage.startIndex
        }
        var endIndex: Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index {
            self.storage.endIndex
        }

        private var storage: Set<TaskInfo> = []

        public init() { }

        mutating func insert(_ task: TaskInfo) {
            storage.insert(task)
        }

        subscript(position: Index) -> Element {
            return storage[position]
        }

        func index(after i: Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index) -> Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index {
            return storage.index(after: i)
        }

        func contains(_ task: TaskInfo) -> Bool {
            return storage.contains(task)
        }

        public func contains(_ taskID: Int) -> Bool {
            return storage.contains(where: { $0.taskID == taskID })
        }

        public func contains(_ taskSignature: String) -> Bool {
            return storage.contains(where: { $0.taskSignature == taskSignature })
        }

        public mutating func insert(_ startedTaskInfo: SwiftBuildMessage.TaskStartedInfo) {
            self.storage.insert(.init(startedTaskInfo))
        }
    }

    struct TaskInfo: Hashable {
        let taskID: Int
        let taskSignature: String

        public init(_ startedTaskInfo: SwiftBuildMessage.TaskStartedInfo) {
            self.taskID = startedTaskInfo.taskID
            self.taskSignature = startedTaskInfo.taskSignature
        }

        public static func ==(lhs: Self, rhs: String) -> Bool {
            return lhs.taskSignature == rhs
        }

        public static func ==(lhs: Self, rhs: Int) -> Bool {
            return lhs.taskID == rhs
        }
    }
}

fileprivate extension SwiftBuild.SwiftBuildMessage.DiagnosticInfo.Location {
    var userDescription: String? {
        switch self {
        case .path(let path, let fileLocation):
            switch fileLocation {
            case .textual(let line, let column):
                var description = "\(path):\(line)"
                if let column { description += ":\(column)" }
                return description
            case .object(let identifier):
                return "\(path):\(identifier)"
            case .none:
                return path
            }

        case .buildSettings(let names):
            return names.joined(separator: ", ")

        case .buildFiles(let buildFiles, let targetGUID):
            return "\(targetGUID): " + buildFiles.map { String(describing: $0) }.joined(separator: ", ")

        case .unknown:
            return nil
        }
    }
}

fileprivate extension BuildSystemCommand {
    init(_ taskStartedInfo: SwiftBuildMessage.TaskStartedInfo, targetInfo: SwiftBuildMessage.TargetStartedInfo?) {
        self = .init(
            name: taskStartedInfo.executionDescription,
            targetName: targetInfo?.targetName,
            description: taskStartedInfo.commandLineDisplayString ?? "",
            serializedDiagnosticPaths: taskStartedInfo.serializedDiagnosticsPaths.compactMap {
                try? Basics.AbsolutePath(validating: $0.pathString)
            }
        )
    }
}

/// Convenience extensions to extract taskID and targetID from the LocationContext.
extension SwiftBuildMessage.LocationContext {
    var taskID: Int? {
        switch self {
        case .task(let id, _), .globalTask(let id):
            return id
        case .target, .global:
            return nil
        }
    }

    var targetID: Int? {
        switch self {
        case .task(_, let id), .target(let id):
            return id
        case .global, .globalTask:
            return nil
        }
    }

    var isGlobal: Bool {
        switch self {
        case .global:
            return true
        case .task, .target, .globalTask:
            return false
        }
    }

    var isTarget: Bool {
        switch self {
        case .target:
            return true
        case .global, .globalTask, .task:
            return false
        }
    }
}
