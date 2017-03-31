/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// A protocol to operate on terminal based progress bars.
public protocol ProgressBarProtocol {
    func update(percent: Int, text: String)
    func complete()
}

/// Simple ProgressBar which shows the update text in new lines.
public final class SimpleProgressBar: ProgressBarProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream

    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }

    public func update(percent: Int, text: String) {
        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

        stream <<< "\(percent)%: " <<< text
        stream <<< "\n"
        stream.flush()
    }

    public func complete() {
    }
}

/// Three line progress bar with header, redraws on each update.
public final class ProgressBar: ProgressBarProtocol {
    private let term: TerminalController
    private let header: String
    private var isClear: Bool // true if haven't drawn anything yet.

    init(term: TerminalController, header: String) {
        self.term = term
        self.header = header
        self.isClear = true
    }

    /// Creates repeating string for count times.
    /// If count is negative, returns empty string.
    private func repeating(string: String, count: Int) -> String {
        return String(repeating: string, count: max(count, 0))
    }

    public func update(percent: Int, text: String) {
        if isClear {
            let spaceCount = (term.width/2 - header.utf8.count/2)
            term.write(repeating(string: " ", count: spaceCount))
            term.write(header, inColor: .cyan, bold: true)
            term.endLine()
            isClear = false
        }

        term.clearLine()
        let percentString = percent < 10 ? " \(percent)" : "\(percent)"
        let prefix = "\(percentString)% " + term.wrap("[", inColor: .green, bold: true)
        term.write(prefix)

        let barWidth = term.width - prefix.utf8.count
        let n = Int(Double(barWidth) * Double(percent)/100.0)

        term.write(repeating(string: "=", count: n) + repeating(string: "-", count: barWidth - n), inColor: .green)
        term.write("]", inColor: .green, bold: true)
        term.endLine()

        term.clearLine()
        term.write(text)

        term.moveCursor(up: 1)
    }

    public func complete() {
        term.endLine()
    }
}

/// Creates colored or simple progress bar based on the provided output stream.
public func createProgressBar(forStream stream: OutputByteStream, header: String) -> ProgressBarProtocol {
    if let stdStream = stream as? LocalFileOutputByteStream, let term = TerminalController(stream: stdStream) {
        return ProgressBar(term: term, header: header)
    }
    return SimpleProgressBar(stream: stream, header: header)
}
