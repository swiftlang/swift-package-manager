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

@_spi(SwiftPMInternal)
import Basics
import Dispatch
import PackageModel

import protocol TSCBasic.OutputByteStream
import class TSCBasic.TerminalController
import class TSCBasic.ThreadSafeOutputByteStream

import class TSCBasic.BufferedOutputByteStream
import class TSCBasic.LocalFileOutputByteStream
import class TSCUtility.MultiLineNinjaProgressAnimation
import class TSCUtility.NinjaProgressAnimation
import protocol TSCUtility.ProgressAnimationProtocol

public struct SwiftCommandObservabilityHandler: ObservabilityHandlerProvider {
    private let outputHandler: OutputHandler

    public var diagnosticsHandler: DiagnosticsHandler {
        self.outputHandler
    }

    /// Initializes a new observability handler provider.
    /// - Parameters:
    ///   - outputStream: an instance of a stream used for output.
    ///   - logLevel: the lowest severity of diagnostics that this handler will forward to `outputStream`. Diagnostics
    ///   emitted below this level will be ignored.

    public init(outputStream: OutputByteStream, logLevel: Basics.Diagnostic.Severity, colorDiagnostics: Bool = true) {
        let threadSafeOutputByteStream = outputStream as? ThreadSafeOutputByteStream ??
            ThreadSafeOutputByteStream(outputStream)
        self.outputHandler = OutputHandler(
            logLevel: logLevel,
            outputStream: threadSafeOutputByteStream,
            colorDiagnostics: colorDiagnostics
        )
    }

    // for raw output reporting
    func print(_ output: String, verbose: Bool) {
        self.outputHandler.print(output, verbose: verbose)
    }

    // for raw progress reporting
    func progress(step: Int64, total: Int64, description: String?) {
        self.outputHandler.progress(step: step, total: total, description: description)
    }

    // FIXME: deprecate this one we are further along refactoring the call sites that use it
    var outputStream: OutputByteStream {
        self.outputHandler.outputStream
    }

    // prompt for user input
    func prompt(_ message: String, completion: (String?) -> Void) {
        self.outputHandler.prompt(message: message, completion: completion)
    }

    public func wait(timeout: DispatchTime) {
        self.outputHandler.wait(timeout: timeout)
    }

    struct OutputHandler {
        private let logLevel: Diagnostic.Severity
        internal let outputStream: ThreadSafeOutputByteStream
        private let writer: InteractiveWriter
        private let progressAnimation: ProgressAnimationProtocol
        private let colorDiagnostics: Bool
        private let queue = DispatchQueue(label: "org.swift.swiftpm.tools-output")
        private let sync = DispatchGroup()

        init(logLevel: Diagnostic.Severity, outputStream: ThreadSafeOutputByteStream, colorDiagnostics: Bool) {
            self.logLevel = logLevel
            self.outputStream = outputStream
            self.writer = InteractiveWriter(stream: outputStream)
            self.progressAnimation = ProgressAnimation.ninja(
                stream: self.outputStream,
                verbose: self.logLevel.isVerbose
            )
            self.colorDiagnostics = colorDiagnostics
        }

        func handleDiagnostic(scope: ObservabilityScope, diagnostic: Basics.Diagnostic) {
            self.queue.async(group: self.sync) {
                guard diagnostic.severity >= self.logLevel else {
                    return
                }

                // TODO: do something useful with scope
                var output: String

                let prefix = diagnostic.severity.logLabel
                let color = self.colorDiagnostics ? diagnostic.severity.color : .noColor
                let bold = self.colorDiagnostics ? diagnostic.severity.isBold : false

                output = self.writer.format(prefix, inColor: color, bold: bold)
                if let diagnosticPrefix = diagnostic.metadata?.diagnosticPrefix {
                    output += diagnosticPrefix
                    output += ": "
                }

                output += diagnostic.message
                self.write(output)
            }
        }

        // for raw output reporting
        func print(_ output: String, verbose: Bool) {
            self.queue.async(group: self.sync) {
                guard !verbose || self.logLevel.isVerbose else {
                    return
                }
                self.write(output)
            }
        }

        // for raw progress reporting
        func progress(step: Int64, total: Int64, description: String?) {
            self.queue.async(group: self.sync) {
                self.progressAnimation.update(
                    step: step > Int.max ? Int.max : Int(step),
                    total: total > Int.max ? Int.max : Int(total),
                    text: description ?? ""
                )
            }
        }

        // to read input from user
        func prompt(message: String, completion: (String?) -> Void) {
            guard self.outputStream.isTTY else {
                return completion(.none)
            }
            let answer = self.queue.sync {
                self.progressAnimation.clear()
                self.outputStream.write(message.utf8)
                self.outputStream.flush()
                return readLine(strippingNewline: true)
            }
            completion(answer)
        }

        func wait(timeout: DispatchTime) {
            switch self.sync.wait(timeout: timeout) {
            case .success:
                break
            case .timedOut:
                self.write("warning: failed to process all diagnostics")
            }
        }

        private func write(_ output: String) {
            self.progressAnimation.clear()
            var output = output
            if !output.hasSuffix("\n") {
                output += "\n"
            }
            self.writer.write(output)
        }
    }
}

extension SwiftCommandObservabilityHandler.OutputHandler: @unchecked Sendable {}
extension SwiftCommandObservabilityHandler.OutputHandler: DiagnosticsHandler {}

/// This type is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
private struct InteractiveWriter {
    /// The terminal controller, if present.
    let term: TerminalController?

    /// The output byte stream reference.
    let stream: OutputByteStream

    /// Create an instance with the given stream.
    init(stream: OutputByteStream) {
        self.term = TerminalController(stream: stream)
        self.stream = stream
    }

    /// Write the string to the contained terminal or stream.
    func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if let term {
            term.write(string, inColor: color, bold: bold)
        } else {
            string.write(to: stream)
            stream.flush()
        }
    }

    func format(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) -> String {
        if let term {
            return term.wrap(string, inColor: color, bold: bold)
        } else {
            return string
        }
    }
}

// FIXME: this is for backwards compatibility with existing diagnostics printing format
// we should remove this as we make use of the new scope and metadata to provide better contextual information
extension ObservabilityMetadata {
    fileprivate var diagnosticPrefix: String? {
        if let packageIdentity {
            return "'\(packageIdentity)'"
        } else {
            return .none
        }
    }
}

extension Basics.Diagnostic.Severity {
    fileprivate var isVerbose: Bool {
        return self <= .info
    }
}
