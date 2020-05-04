/*
This source file is part of the Swift.org open source project

Copyright (c) 2020 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See http://swift.org/LICENSE.txt for license information
See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import TSCBasic
import TSCUtility

public class XCBuildDelegate {
    private var parser: XCBuildOutputParser!
    private let diagnostics: DiagnosticsEngine
    private let outputStream: ThreadSafeOutputByteStream
    private let progressAnimation: ProgressAnimationProtocol
    private var percentComplete: Int = 0
    private let queue = DispatchQueue(label: "org.swift.swiftpm.xcbuild-delegate")

    /// Whether to print more informationr regarding the build.
    public var isVerbose: Bool = false

    /// True if any progress output was emitted.
    fileprivate var didEmitProgressOutput: Bool = false

    public init(
        diagnostics: DiagnosticsEngine,
        outputStream: OutputByteStream,
        progressAnimation: ProgressAnimationProtocol
    ) {
        self.diagnostics = diagnostics
        // FIXME: Implement a class convenience initializer that does this once they are supported
        // https://forums.swift.org/t/allow-self-x-in-class-convenience-initializers/15924
        self.outputStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.progressAnimation = progressAnimation
        parser = XCBuildOutputParser(delegate: self)
    }

    public func parse(bytes: [UInt8]) {
        parser.parse(bytes: bytes)
    }
}

extension XCBuildDelegate: XCBuildOutputParserDelegate {
    public func xcBuildOutputParser(_ parser: XCBuildOutputParser, didParse message: XCBuildMessage) {
        switch message {
        case .taskStarted(let info):
            queue.async {
                self.didEmitProgressOutput = true
                let text = self.isVerbose ? info.executionDescription + "\n" + info.commandLineDisplayString : info.executionDescription
                self.progressAnimation.update(step: self.percentComplete, total: 100, text: text)
            }
        case .taskOutput(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream <<< info.data
                self.outputStream <<< "\n"
                self.outputStream.flush()
            }
        case .buildDiagnostic(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream <<< info.message
                self.outputStream <<< "\n"
                self.outputStream.flush()
            }
        case .buildOutput(let info):
            queue.async {
                self.progressAnimation.clear()
                self.outputStream <<< info.data
                self.outputStream <<< "\n"
                self.outputStream.flush()
            }
        case .didUpdateProgress(let info):
            queue.async {
                let percent = Int(info.percentComplete)
                self.percentComplete = percent > 0 ? percent : 0
            }
        case .buildCompleted(let info):
            queue.async {
                switch info.result {
                case .aborted, .cancelled, .failed:
                    self.outputStream <<< "Build \(info.result)\n"
                    self.outputStream.flush()
                case .ok:
                    if self.didEmitProgressOutput {
                        self.progressAnimation.update(step: 100, total: 100, text: "Build succeeded")
                    }
                }
            }
        default:
            break
        }
    }

    public func xcBuildOutputParser(_ parser: XCBuildOutputParser, didFailWith error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        diagnostics.emit(.xcbuildOutputParsingError(message))
    }
}

private extension Diagnostic.Message {
    static func xcbuildOutputParsingError(_ error: String) -> Diagnostic.Message {
        .error("failed parsing XCBuild output: \(error)")
    }
}

// FIXME: Move to TSC.
public final class VerboseProgressAnimation: ProgressAnimationProtocol {

    private let stream: OutputByteStream

    public init(stream: OutputByteStream) {
        self.stream = stream
    }

    public func update(step: Int, total: Int, text: String) {
        stream <<< text <<< "\n"
        stream.flush()
    }

    public func complete(success: Bool) {
        stream <<< "\n"
        stream.flush()
    }

    public func clear() {
    }
}
