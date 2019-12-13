/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import PackageLoading
import PackageModel
import SourceControl
import TSCUtility
import func TSCLibc.exit
import Workspace

enum Error: Swift.Error {
    /// Couldn't find all tools needed by the package manager.
    case invalidToolchain(problem: String)

    /// The root manifest was not found.
    case rootManifestFileNotFound
}

extension Error: CustomStringConvertible {
    var description: String {
        switch self {
        case .invalidToolchain(let problem):
            return problem
        case .rootManifestFileNotFound:
            return "root manifest not found"
        }
    }
}

// The name has underscore because of SR-4015.
func handle(error: Swift.Error) {

    switch error {
    case Diagnostics.fatalError:
        break

    case ArgumentParserError.expectedArguments(let parser, _):
        print(error: error)
        parser.printUsage(on: stderrStream)

    default:
        print(error: error)
    }
}

func print(error: Any) {
    let writer = InteractiveWriter.stderr
    writer.write("error: ", inColor: .red, bold: true)
    writer.write("\(error)")
    writer.write("\n")
}

func print(diagnostic: Diagnostic, stdoutStream: OutputByteStream) {

    let writer = InteractiveWriter.stderr

    if !(diagnostic.location is UnknownLocation) {
        writer.write(diagnostic.location.description)
        writer.write(": ")
    }

    switch diagnostic.message.behavior {
    case .error:
        writer.write("error: ", inColor: .red, bold: true)
    case .warning:
        writer.write("warning: ", inColor: .yellow, bold: true)
    case .note:
        writer.write("note: ", inColor: .yellow, bold: true)
    case .remark:
        writer.write("remark: ", inColor: .yellow, bold: true)
    case .ignored:
        break
    }

    writer.write(diagnostic.description)
    writer.write("\n")
}

/// This class is used to write on the underlying stream.
///
/// If underlying stream is a not tty, the string will be written in without any
/// formatting.
private final class InteractiveWriter {

    /// The standard error writer.
    static let stderr = InteractiveWriter(stream: stderrStream)

    /// The standard output writer.
    static let stdout = InteractiveWriter(stream: stdoutStream)

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
        if let term = term {
            term.write(string, inColor: color, bold: bold)
        } else {
            stream <<< string
            stream.flush()
        }
    }
}
