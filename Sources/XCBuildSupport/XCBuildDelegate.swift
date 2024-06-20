//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import SPMBuildCore

import class TSCBasic.ThreadSafeOutputByteStream
import protocol TSCBasic.OutputByteStream

import enum TSCUtility.Diagnostics
import protocol TSCUtility.ProgressAnimationProtocol

public class XCBuildDelegate {
    private let buildSystem: SPMBuildCore.BuildSystem
    private var parser: XCBuildOutputParser!
    private let observabilityScope: ObservabilityScope
    private let outputStream: ThreadSafeOutputByteStream
    private let progressAnimation: ProgressAnimationProtocol
    private var percentComplete: Int = 0
    private let queue = DispatchQueue(label: "org.swift.swiftpm.xcbuild-delegate")

    /// The verbosity level to print out at
    private let logLevel: Basics.Diagnostic.Severity

    /// True if any progress output was emitted.
    fileprivate var didEmitProgressOutput: Bool = false

    /// True if any output was parsed.
    fileprivate(set) var didParseAnyOutput: Bool = false

    public init(
        buildSystem: SPMBuildCore.BuildSystem,
        outputStream: OutputByteStream,
        progressAnimation: ProgressAnimationProtocol,
        logLevel: Basics.Diagnostic.Severity,
        observabilityScope: ObservabilityScope
    ) {
        self.buildSystem = buildSystem
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.outputStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.progressAnimation = progressAnimation
        self.logLevel = logLevel
        self.observabilityScope = observabilityScope
        self.parser = XCBuildOutputParser(delegate: self)
    }

    public func parse(bytes: [UInt8]) {
        parser.parse(bytes: bytes)
    }
}

extension XCBuildDelegate: XCBuildOutputParserDelegate {
    public func xcBuildOutputParser(_ parser: XCBuildOutputParser, didParse message: XCBuildMessage) {
        self.didParseAnyOutput = true

        switch message {
        case .taskStarted(let info):
            queue.async {
                self.didEmitProgressOutput = true
                let text = self.logLevel.isVerbose ? [info.executionDescription, info.commandLineDisplayString].compactMap { $0 }.joined(separator: "\n") : info.executionDescription
                self.progressAnimation.update(step: self.percentComplete, total: 100, text: text)
                self.buildSystem.delegate?.buildSystem(self.buildSystem, willStartCommand: BuildSystemCommand(name: "\(info.taskID)", description: info.executionDescription, verboseDescription: info.commandLineDisplayString))
                self.buildSystem.delegate?.buildSystem(self.buildSystem, didStartCommand: BuildSystemCommand(name: "\(info.taskID)", description: info.executionDescription, verboseDescription: info.commandLineDisplayString))
            }
        case .taskOutput(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream.send("\(info.data)\n")
                self.outputStream.flush()
            }
        case .taskComplete(let info):
            queue.async {
                self.buildSystem.delegate?.buildSystem(self.buildSystem, didFinishCommand: BuildSystemCommand(name: "\(info.taskID)", description: info.result.rawValue))
            }
        case .buildDiagnostic(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream.send("\(info.message)\n")
                self.outputStream.flush()
            }
        case .taskDiagnostic(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream.send("\(info.message)\n")
                self.outputStream.flush()
            }
        case .targetDiagnostic(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream.send("\(info.message)\n")
                self.outputStream.flush()
            }
        case .buildOutput(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream.send("\(info.data)\n")
                self.outputStream.flush()
            }
        case .didUpdateProgress(let info):
            queue.async {
                let percent = Int(info.percentComplete)
                self.percentComplete = percent > 0 ? percent : 0
                self.buildSystem.delegate?.buildSystem(self.buildSystem, didUpdateTaskProgress: info.message)
            }
        case .buildCompleted(let info):
            queue.async {
                switch info.result {
                case .aborted, .cancelled, .failed:
                    self.outputStream.send("Build \(info.result)\n")
                    self.outputStream.flush()
                    self.buildSystem.delegate?.buildSystem(self.buildSystem, didFinishWithResult: false)
                case .ok:
                    if self.didEmitProgressOutput {
                        self.progressAnimation.update(step: 100, total: 100, text: "Build succeeded")
                    }
                    self.buildSystem.delegate?.buildSystem(self.buildSystem, didFinishWithResult: true)
                }
            }
        case .buildStarted, .preparationComplete, .targetUpToDate, .targetStarted, .targetComplete, .taskUpToDate, .unknown:
            break
        }
    }

    public func xcBuildOutputParser(_ parser: XCBuildOutputParser, didFailWith error: Error) {
        self.didParseAnyOutput = true
        self.observabilityScope.emit(.xcbuildOutputParsingError(error))
    }
}

private extension Basics.Diagnostic {
    static func xcbuildOutputParsingError(_ error: Error) -> Self {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return .error("failed parsing XCBuild output: \(message)")
    }
}

@available(*, deprecated, message: "use ProgressAnimation.ninja(stream:) instead")
public final class VerboseProgressAnimation: ProgressAnimationProtocol {
    private let stream: OutputByteStream

    public init(stream: OutputByteStream) {
        self.stream = stream
    }

    public func update(step: Int, total: Int, text: String) {
        stream.send("\(text)\n")
        stream.flush()
    }

    public func complete(success: Bool) {
        stream.send("\n")
        stream.flush()
    }

    public func clear() {
    }
}
