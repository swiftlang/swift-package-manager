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
    func complete(success: Bool)
}

/// A single line progress bar.
///
/// On a new line from the `header` (if provided) SingleLineProgressBar
/// shows simply the passed percent. For example,
///
///     let progressBar = SingleLineProgressBar(stream: stdoutStream, header: "Foo")
///     progressBar.update(percent: 40, text: "Starting")
///     progressBar.update(percent: 40, text: "Checking")
///     progressBar.update(percent: 90, text: "Finishing")
///     progressBar.update(percent: 100, text: "Done")
///     progressBar.complete(success: true)
///
/// Displays
///
///     Foo
///     40.. 90.. OK
///
/// - Warning: Only the progress bar is a single line. The header
///            is displayed on it's own line.
public final class SingleLineProgressBar: ProgressBarProtocol {
    private let header: String
    private var isClear: Bool
    private var stream: OutputByteStream
    private var displayed: Set<Int> = []
    
    /// Create a SimpleLineProgress to `stream`
    ///
    ///
    /// - Parameters:
    ///   - stream: Destination stream for bar.
    ///   - header: Informative text preceding the bar.
    init(stream: OutputByteStream, header: String) {
        self.stream = stream
        self.header = header
        self.isClear = true
    }
    
    /// Updates the progress bar.
    ///
    /// - Parameters:
    ///   - percent: Number between 0 and 100
    ///   - text: Informative text about the update. Ignored in
    ///           SingleLineProgressBar
    /// - Note: Repeat percentages are not displayed again.
    public func update(percent: Int, text: String) {
        if isClear {
            stream <<< header
            stream <<< "\n"
            stream.flush()
            isClear = false
        }

        let displayPercentage = Int(Double(percent / 10).rounded(.down)) * 10
        if percent != 100, !displayed.contains(displayPercentage) {
            stream <<< String(displayPercentage) <<< ".. "
            displayed.insert(displayPercentage)
        }
        stream.flush()
    }
    
    /// Marks the progress as completed.
    ///
    /// Will display "OK" is `success` is true.
    ///
    /// - Parameter success: Whether the operation was a success.
    public func complete(success: Bool) {
        if success {
            stream <<< "OK"
            stream.flush()
        }
    }
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

    public func complete(success: Bool) {
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
        if text.utf8.count > term.width {
            let prefix = "…"
            term.write(prefix)
            term.write(String(text.suffix(term.width - prefix.utf8.count)))
        } else {
            term.write(text)
        }

        term.moveCursor(up: 1)
    }

    public func complete(success: Bool) {
        term.endLine()
        term.endLine()
    }
}

/// Creates colored or simple progress bar based on the provided output stream.
public func createProgressBar(forStream stream: OutputByteStream, header: String) -> ProgressBarProtocol {
    // If we have a terminal, use animated progress bar.
    if let term = TerminalController(stream: stream) {
        return ProgressBar(term: term, header: header)
    }

    // If the terminal is dumb, use single line progress bar.
    if let fileStream = stream as? LocalFileOutputByteStream, TerminalController.terminalType(fileStream) == .dumb {
        return SingleLineProgressBar(stream: stream, header: header)
    }

    // Use simple progress bar by default.
    return SimpleProgressBar(stream: stream, header: header)
}
