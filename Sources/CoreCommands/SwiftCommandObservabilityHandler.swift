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

import protocol TSCBasic.OutputByteStream
import class TSCBasic.TerminalController
import class TSCBasic.ThreadSafeOutputByteStream

import class TSCUtility.MultiLineNinjaProgressAnimation
import class TSCUtility.NinjaProgressAnimation
import protocol TSCUtility.ProgressAnimationProtocol
import class TSCBasic.LocalFileOutputByteStream
import class TSCBasic.BufferedOutputByteStream
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
<<<<<<< HEAD
    public init(outputStream: OutputByteStream, logLevel: Basics.Diagnostic.Severity) {
        let threadSafeOutputByteStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.outputHandler = OutputHandler(logLevel: logLevel, outputStream: threadSafeOutputByteStream)
=======
    public init(outputStream: OutputByteStream, logLevel: Basics.Diagnostic.Severity, colorDiagnostics: Bool = true, manualWriterParams: [String: Bool] = ["use": false]) {
        let threadSafeOutputByteStream = outputStream as? ThreadSafeOutputByteStream ?? ThreadSafeOutputByteStream(outputStream)
        self.outputHandler = OutputHandler(logLevel: logLevel, outputStream: threadSafeOutputByteStream, colorDiagnostics: colorDiagnostics, manualWriterParams: manualWriterParams)
>>>>>>> 15e3b6455 (fixed color output diagnostics, along with tests)
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
        private let writer: Writable
        private let progressAnimation: ProgressAnimationProtocol
<<<<<<< HEAD

        private let queue = DispatchQueue(label: "org.swift.swiftpm.tools-output")
        private let sync = DispatchGroup()

        init(logLevel: Diagnostic.Severity, outputStream: ThreadSafeOutputByteStream) {
=======
        private let colorDiagnostics: Bool
        private let queue = DispatchQueue(label: "org.swift.swiftpm.tools-output")
        private let sync = DispatchGroup()

        init(logLevel: Diagnostic.Severity, outputStream: ThreadSafeOutputByteStream, colorDiagnostics: Bool, manualWriterParams: [String: Bool]) {
>>>>>>> 15e3b6455 (fixed color output diagnostics, along with tests)
            self.logLevel = logLevel
            self.outputStream = outputStream
            if manualWriterParams["manual"] ?? false {
                self.writer = ManualWriter(isTTY: manualWriterParams["isTTY"] ?? false, stream: outputStream)
            } else {
                self.writer = InteractiveWriter(stream: outputStream)
            }
            self.progressAnimation = ProgressAnimation.ninja(
                stream: self.outputStream,
                verbose: self.logLevel.isVerbose
            )
<<<<<<< HEAD
=======
            self.colorDiagnostics = colorDiagnostics
>>>>>>> 15e3b6455 (fixed color output diagnostics, along with tests)
        }

        func handleDiagnostic(scope: ObservabilityScope, diagnostic: Basics.Diagnostic) {
            self.queue.async(group: self.sync) {
                guard diagnostic.severity >= self.logLevel else {
                    return
                }

                // TODO: do something useful with scope
                var output: String
<<<<<<< HEAD
                switch diagnostic.severity {
                case .error:
                    output = self.writer.format("error: ", inColor: .red, bold: true)
                case .warning:
                    output = self.writer.format("warning: ", inColor: .yellow, bold: true)
                case .info:
                    output = self.writer.format("info: ", inColor: .white, bold: true)
                case .debug:
                    output = self.writer.format("debug: ", inColor: .white, bold: true)
                }
=======
                
                let prefix = diagnostic.severity.prefix
                let color = self.colorDiagnostics ? diagnostic.severity.color : .noColor
                let bold = self.colorDiagnostics ? diagnostic.severity.isBold : false

                output = self.writer.format(prefix, inColor: color, bold: bold)
>>>>>>> 15e3b6455 (fixed color output diagnostics, along with tests)

                if let diagnosticPrefix = diagnostic.metadata?.diagnosticPrefix {
                    output += diagnosticPrefix
                    output += ": "
                }

                output += diagnostic.message
                self.write(output)
            }
        }
<<<<<<< HEAD

=======
>>>>>>> 15e3b6455 (fixed color output diagnostics, along with tests)
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
///
///
private class Writable {
    var isTTY: Bool
    let stream: OutputByteStream

    init(isTTY: Bool = true, stream: OutputByteStream) {
        self.isTTY = isTTY
        self.stream = stream
    }

    func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if isTTY {
            let stringColor = getColorString(color: color)
            stream.send(stringColor).send(bold ? "\u{001B}[1m" : "").send(string).send("\u{001B}[0m")
        } else {
            string.write(to: stream)
            stream.flush()
        }
    }

    func format(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) -> String {
        if isTTY {
            let stringColor = getColorString(color: color)
            guard !string.isEmpty && color != .noColor else {
                return string
            }
            return "\(stringColor)\(bold ? "\u{001B}[1m" : "")\(string)\u{001B}[0m"
        } else {
            return string
        }
    }

    private func getColorString(color: TerminalController.Color) -> String {
        switch color {
            case .noColor: return ""
            case .red: return "\u{001B}[31m"
            case .green: return "\u{001B}[32m"
            case .yellow: return "\u{001B}[33m"
            case .cyan: return "\u{001B}[36m"
            case .white: return "\u{001B}[37m"
            case .black: return "\u{001B}[30m"
            case .gray: return "\u{001B}[30;1m"
        }
    }
}

private class ManualWriter: Writable {
    override init(isTTY: Bool = true, stream: OutputByteStream) {
        super.init(isTTY: isTTY, stream: stream)
    }

    public func setTTYMode(_ mode: Bool) {
        self.isTTY = mode
    }
}

private class InteractiveWriter: Writable {
    let term: TerminalController?

    init(stream: OutputByteStream) {
        self.term = TerminalController(stream: stream)
        super.init(stream: stream)
    }

    override func write(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) {
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            string.write(to: stream)
            stream.flush()
        }
    }

    override func format(_ string: String, inColor color: TerminalController.Color = .noColor, bold: Bool = false) -> String {
        if let term = term {
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
