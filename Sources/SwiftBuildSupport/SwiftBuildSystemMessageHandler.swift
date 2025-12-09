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
    private let enableBacktraces: Bool
    private let buildDelegate: SPMBuildCore.BuildSystemDelegate?

    public typealias BuildSystemCallback = (SwiftBuildSystem) -> Void

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
        logLevel: Basics.Diagnostic.Severity,
        enableBacktraces: Bool,
        buildDelegate: SPMBuildCore.BuildSystemDelegate? = nil
    )
    {
        self.observabilityScope = observabilityScope
        self.logLevel = logLevel
        self.progressAnimation = ProgressAnimation.ninja(
            stream: outputStream,
            verbose: self.logLevel.isVerbose
        )
        self.enableBacktraces = enableBacktraces
        self.buildDelegate = buildDelegate
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

    public func emitEvent(_ message: SwiftBuild.SwiftBuildMessage) throws -> BuildSystemCallback? {
        var callback: BuildSystemCallback? = nil

        guard !self.logLevel.isQuiet else { return callback }
        switch message {
        case .buildCompleted(let info):
            progressAnimation.complete(success: info.result == .ok)
            if info.result == .cancelled {
                callback = { [weak self] buildSystem in
                    self?.buildDelegate?.buildSystemDidCancel(buildSystem)
                }
            } else {
                callback = { [weak self] buildSystem in
                    self?.buildDelegate?.buildSystem(buildSystem, didFinishWithResult: info.result == .ok)
                }
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
            callback = { [weak self] buildSystem in
                self?.buildDelegate?.buildSystem(buildSystem, didUpdateTaskProgress: message)
            }
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
            callback = { [weak self] buildSystem in
                self?.buildDelegate?.buildSystem(buildSystem, willStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
                self?.buildDelegate?.buildSystem(buildSystem, didStartCommand: BuildSystemCommand(info, targetInfo: targetInfo))
            }
        case .taskComplete(let info):
            let startedInfo = try buildState.completed(task: info)

            // Handler for failed tasks, if applicable.
            try handleTaskOutput(info, startedInfo, self.enableBacktraces)

            let targetInfo = try buildState.target(for: startedInfo)
            callback = { [weak self] buildSystem in
                self?.buildDelegate?.buildSystem(buildSystem, didFinishCommand: BuildSystemCommand(startedInfo, targetInfo: targetInfo))
            }
            if let targetID = targetInfo?.targetID {
                try serializedDiagnosticPathsByTargetID[targetID, default: []].append(contentsOf: startedInfo.serializedDiagnosticsPaths.compactMap {
                    try Basics.AbsolutePath(validating: $0.pathString)
                })
            }
        case .targetStarted(let info):
            try buildState.started(target: info)
        case .backtraceFrame(let info):
            if self.enableBacktraces {
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
        
        return callback
    }
}

// MARK: SwiftBuildSystemMessageHandler.BuildState

extension SwiftBuildSystemMessageHandler {
    /// Manages the state of an active build operation, tracking targets, tasks, buffers, and backtrace frames.
    /// This struct maintains the complete state model for build operations, coordinating data between
    /// different phases of the build lifecycle.
    struct BuildState {
        // Targets
        internal var targetsByID: [Int: SwiftBuild.SwiftBuildMessage.TargetStartedInfo] = [:]
        private var completedTargets: [Int: SwiftBuild.SwiftBuildMessage.TargetCompleteInfo] = [:]

        // Tasks
        private var activeTasks: [Int: SwiftBuild.SwiftBuildMessage.TaskStartedInfo] = [:]
        private var completedTasks: [Int: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo] = [:]
        private var taskIDToSignature: [Int: String] = [:]

        // Per-task buffers
        private var taskDataBuffer: TaskDataBuffer = .init()
        private var diagnosticsBuffer: TaskDiagnosticBuffer = .init()

        // Backtrace frames
        internal var collectedBacktraceFrames = SWBBuildOperationCollectedBacktraceFrames()

        /// Registers the start of a build task, validating that the task hasn't already been started.
        /// - Parameter task: The task start information containing task ID and signature
        /// - Throws: Fatal error if the task is already active
        mutating func started(task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws {
            if activeTasks[task.taskID] != nil {
                throw Diagnostics.fatalError
            }
            activeTasks[task.taskID] = task
            taskIDToSignature[task.taskID] = task.taskSignature
        }

        /// Marks a task as completed and removes it from active tracking.
        /// - Parameter task: The task completion information
        /// - Returns: The original task start information for the completed task
        /// - Throws: Fatal error if the task was not started or already completed
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

        /// Registers the start of a build target, validating that the target hasn't already been started.
        /// - Parameter target: The target start information containing target ID and name
        /// - Throws: Fatal error if the target is already active
        mutating func started(target: SwiftBuild.SwiftBuildMessage.TargetStartedInfo) throws {
            if targetsByID[target.targetID] != nil {
                throw Diagnostics.fatalError
            }
            targetsByID[target.targetID] = target
        }

        /// Marks a target as completed and removes it from active tracking.
        /// - Parameter target: The target completion information
        /// - Returns: The original target start information for the completed target
        /// - Throws: Fatal error if the target was not started
        mutating func completed(target: SwiftBuild.SwiftBuildMessage.TargetCompleteInfo) throws -> SwiftBuild.SwiftBuildMessage.TargetStartedInfo {
            guard let targetStartedInfo = targetsByID[target.targetID] else {
                throw Diagnostics.fatalError
            }

            targetsByID[target.targetID] = nil
            completedTargets[target.targetID] = target
            return targetStartedInfo
        }

        /// Retrieves the target information associated with a given task.
        /// - Parameter task: The task start information to look up the target for
        /// - Returns: The target start information if the task has an associated target, nil otherwise
        /// - Throws: Fatal error if the target ID exists but no matching target is found
        func target(for task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) throws -> SwiftBuild.SwiftBuildMessage.TargetStartedInfo? {
            guard let id = task.targetID else {
                return nil
            }
            guard let target = targetsByID[id] else {
                throw Diagnostics.fatalError
            }
            return target
        }

        /// Retrieves the task signature for a given task ID.
        /// - Parameter id: The task ID to look up
        /// - Returns: The task signature string if found, nil otherwise
        func taskSignature(for id: Int) -> String? {
            if let signature = taskIDToSignature[id] {
                return signature
            }
            return nil
        }
    }
}

// MARK: - SwiftBuildSystemMessageHandler.BuildState.TaskDataBuffer

extension SwiftBuildSystemMessageHandler.BuildState {
    /// Manages data buffers for build tasks, supporting multiple indexing strategies.
    /// This buffer system stores output data from tasks using both task signatures and task IDs,
    /// providing flexible access patterns for different build message types and legacy support.
    struct TaskDataBuffer {
        private var taskSignatureBuffer: [String: Data] = [:]
        private var taskIDBuffer: [Int: Data] = [:]

        /// Retrieves data for a task signature key.
        /// - Parameter key: The task signature string
        /// - Returns: The associated data buffer, or nil if not found
        subscript(key: String) -> Data? {
            self.taskSignatureBuffer[key]
        }

        /// Retrieves or sets data for a task signature key with a default value.
        /// - Parameters:
        ///   - key: The task signature string
        ///   - defaultValue: The default data to return/store if no value exists
        /// - Returns: The stored data buffer or the default value
        subscript(key: String, default defaultValue: Data) -> Data {
            get { self.taskSignatureBuffer[key] ?? defaultValue }
            set { self.taskSignatureBuffer[key] = newValue }
        }

        /// Retrieves or sets data using a LocationContext for task identification.
        /// - Parameters:
        ///   - key: The location context containing task or target ID information
        ///   - defaultValue: The default data to return/store if no value exists
        /// - Returns: The stored data buffer or the default value
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

        /// Retrieves or sets data using a LocationContext2 for task identification.
        /// - Parameter key: The location context containing task signature information
        /// - Returns: The associated data buffer, or nil if not found
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

        /// Retrieves data for a specific task using TaskStartedInfo.
        /// - Parameter task: The task start information containing signature and ID
        /// - Returns: The associated data buffer, or nil if not found
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

    /// Appends output data to the appropriate task buffer based on location context information.
    /// - Parameter info: The output info containing data and location context for storage
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

    /// Retrieves the accumulated data buffer for a specific task.
    /// - Parameter task: The task start information to look up data for
    /// - Returns: The accumulated data buffer for the task, or nil if no data exists
    func dataBuffer(for task: SwiftBuild.SwiftBuildMessage.TaskStartedInfo) -> Data? {
        guard let data = taskDataBuffer[task.taskSignature] else {
            // Fallback to checking taskID and targetID.
            return taskDataBuffer[task]
        }

        return data
    }

}

// MARK: - SwiftBuildSystemMessageHandler.BuildState.TaskDiagnosticBuffer

extension SwiftBuildSystemMessageHandler.BuildState {
    /// Manages diagnostic information buffers for build tasks, organized by task signatures and IDs.
    /// This buffer system collects diagnostic messages during task execution for later retrieval
    /// and structured reporting of build errors, warnings, and other diagnostic information.
    struct TaskDiagnosticBuffer {
        private var diagnosticSignatureBuffer: [String: [SwiftBuildMessage.DiagnosticInfo]] = [:]
        private var diagnosticIDBuffer: [Int: [SwiftBuildMessage.DiagnosticInfo]] = [:]

        /// Retrieves diagnostic information using LocationContext2 for task identification.
        /// - Parameter key: The location context containing task signature information
        /// - Returns: Array of diagnostic info for the task, or nil if not found
        subscript(key: SwiftBuildMessage.LocationContext2) -> [SwiftBuildMessage.DiagnosticInfo]? {
            guard let taskSignature = key.taskSignature else {
                return nil
            }
            return self.diagnosticSignatureBuffer[taskSignature]
        }

        /// Retrieves or sets diagnostic information using LocationContext2 with a default value.
        /// - Parameters:
        ///   - key: The location context containing task signature information
        ///   - defaultValue: The default diagnostic array to return if no value exists
        /// - Returns: Array of diagnostic info for the task, or the default value
        subscript(key: SwiftBuildMessage.LocationContext2, default defaultValue: [SwiftBuildMessage.DiagnosticInfo]) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self[key] ?? defaultValue }
            set {
                self[key, default: defaultValue]
            }
        }

        /// Retrieves diagnostic information using LocationContext for task identification.
        /// - Parameter key: The location context containing task ID information
        /// - Returns: Array of diagnostic info for the task, or nil if not found
        subscript(key: SwiftBuildMessage.LocationContext) -> [SwiftBuildMessage.DiagnosticInfo]? {
            guard let taskID = key.taskID else {
                return nil
            }

            return self.diagnosticIDBuffer[taskID]
        }

        /// Retrieves diagnostic information using LocationContext with a default value.
        /// - Parameters:
        ///   - key: The location context containing task ID information
        ///   - defaultValue: The default diagnostic array to return if no value exists
        /// - Returns: Array of diagnostic info for the task, or the default value
        subscript(key: SwiftBuildMessage.LocationContext, default defaultValue: [SwiftBuildMessage.DiagnosticInfo]) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self[key] ?? defaultValue }
        }

        /// Retrieves or sets diagnostic information using a task signature string.
        /// - Parameter key: The task signature string
        /// - Returns: Array of diagnostic info for the task signature
        subscript(key: String) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self.diagnosticSignatureBuffer[key] ?? [] }
            set { self.diagnosticSignatureBuffer[key] = newValue }
        }

        /// Retrieves or sets diagnostic information using a task ID.
        /// - Parameter key: The task ID
        /// - Returns: Array of diagnostic info for the task ID
        subscript(key: Int) -> [SwiftBuildMessage.DiagnosticInfo] {
            get { self.diagnosticIDBuffer[key] ?? [] }
            set { self.diagnosticIDBuffer[key] = newValue }
        }
    }

    /// Appends a diagnostic message to the appropriate diagnostic buffer.
    /// - Parameter info: The diagnostic information to store, containing location context for identification
    mutating func appendDiagnostic(_ info: SwiftBuildMessage.DiagnosticInfo) {
        guard let taskID = info.locationContext.taskID else {
            return
        }

        diagnosticsBuffer[taskID].append(info)
    }

    /// Retrieves all diagnostic information for a completed task.
    /// - Parameter task: The task completion information containing the task ID
    /// - Returns: Array of diagnostic info associated with the task
    func diagnostics(for task: SwiftBuild.SwiftBuildMessage.TaskCompleteInfo) -> [SwiftBuildMessage.DiagnosticInfo] {
        return diagnosticsBuffer[task.taskID]
    }
}

// MARK: - SwiftBuildSystemMessageHandler.EmittedTasks

extension SwiftBuildSystemMessageHandler {
    /// A collection that tracks tasks for which output has already been emitted to prevent duplicate output.
    /// This struct ensures that task output is only displayed once during the build process, improving
    /// the readability and accuracy of build logs by avoiding redundant messaging.
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

        /// Inserts a task info into the emitted tasks collection.
        /// - Parameter task: The task information to mark as emitted
        mutating func insert(_ task: TaskInfo) {
            storage.insert(task)
        }

        subscript(position: Index) -> Element {
            return storage[position]
        }

        func index(after i: Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index) -> Set<SwiftBuildSystemMessageHandler.TaskInfo>.Index {
            return storage.index(after: i)
        }

        /// Checks if a specific task info has been marked as emitted.
        /// - Parameter task: The task information to check
        /// - Returns: True if the task has already been emitted, false otherwise
        func contains(_ task: TaskInfo) -> Bool {
            return storage.contains(task)
        }

        /// Checks if a task with the given ID has been marked as emitted.
        /// - Parameter taskID: The task ID to check
        /// - Returns: True if a task with this ID has already been emitted, false otherwise
        public func contains(_ taskID: Int) -> Bool {
            return storage.contains(where: { $0.taskID == taskID })
        }

        /// Checks if a task with the given signature has been marked as emitted.
        /// - Parameter taskSignature: The task signature to check
        /// - Returns: True if a task with this signature has already been emitted, false otherwise
        public func contains(_ taskSignature: String) -> Bool {
            return storage.contains(where: { $0.taskSignature == taskSignature })
        }

        /// Convenience method to insert a task using TaskStartedInfo.
        /// - Parameter startedTaskInfo: The task start information to mark as emitted
        public mutating func insert(_ startedTaskInfo: SwiftBuildMessage.TaskStartedInfo) {
            self.storage.insert(.init(startedTaskInfo))
        }
    }

    /// Represents essential identifying information for a build task.
    /// This struct encapsulates both the numeric task ID and string task signature,
    /// providing efficient lookup and comparison capabilities for task tracking.
    struct TaskInfo: Hashable {
        let taskID: Int
        let taskSignature: String

        /// Initializes TaskInfo from TaskStartedInfo.
        /// - Parameter startedTaskInfo: The task start information containing ID and signature
        public init(_ startedTaskInfo: SwiftBuildMessage.TaskStartedInfo) {
            self.taskID = startedTaskInfo.taskID
            self.taskSignature = startedTaskInfo.taskSignature
        }

        /// Compares TaskInfo with a task signature string.
        /// - Parameters:
        ///   - lhs: The TaskInfo instance
        ///   - rhs: The task signature string to compare
        /// - Returns: True if the TaskInfo's signature matches the string
        public static func ==(lhs: Self, rhs: String) -> Bool {
            return lhs.taskSignature == rhs
        }

        /// Compares TaskInfo with a task ID integer.
        /// - Parameters:
        ///   - lhs: The TaskInfo instance
        ///   - rhs: The task ID integer to compare
        /// - Returns: True if the TaskInfo's ID matches the integer
        public static func ==(lhs: Self, rhs: Int) -> Bool {
            return lhs.taskID == rhs
        }
    }
}

/// Convenience extensions to extract taskID and targetID from the LocationContext.
extension SwiftBuildMessage.LocationContext {
    /// Extracts the task ID from the location context.
    /// - Returns: The task ID if the context represents a task or global task, nil otherwise
    var taskID: Int? {
        switch self {
        case .task(let id, _), .globalTask(let id):
            return id
        case .target, .global:
            return nil
        }
    }

    /// Extracts the target ID from the location context.
    /// - Returns: The target ID if the context represents a task or target, nil otherwise
    var targetID: Int? {
        switch self {
        case .task(_, let id), .target(let id):
            return id
        case .global, .globalTask:
            return nil
        }
    }

    /// Determines if the location context represents a global scope.
    /// - Returns: True if the context is global, false otherwise
    var isGlobal: Bool {
        switch self {
        case .global:
            return true
        case .task, .target, .globalTask:
            return false
        }
    }

    /// Determines if the location context represents a target scope.
    /// - Returns: True if the context is target-specific, false otherwise
    var isTarget: Bool {
        switch self {
        case .target:
            return true
        case .global, .globalTask, .task:
            return false
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
