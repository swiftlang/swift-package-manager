/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc
import func POSIX.getenv

/// A class to have better control on tty output streams: standard output and standard error.
/// Allows operations like cursor movement and colored text output on tty.
public final class TerminalController {

    /// Terminal color choices.
    public enum Color {
        case noColor

        case red
        case green
        case yellow
        case cyan

        case white
        case black
        case grey

        /// Returns the color code which can be prefixed on a string to display it in that color.
        fileprivate var string: String {
            switch self {
                case .noColor: return ""
                case .red: return "\u{001B}[31m"
                case .green: return "\u{001B}[32m"
                case .yellow: return "\u{001B}[33m"
                case .cyan: return "\u{001B}[36m"
                case .white: return "\u{001B}[37m"
                case .black: return "\u{001B}[30m"
                case .grey: return "\u{001B}[30;1m"
            }
        }
    }

    /// Pointer to output stream to operate on.
    private var stream: LocalFileOutputByteStream

    /// Width of the terminal.
    public let width: Int

    /// Code to clear the line on a tty.
    private let clearLineString = "\u{001B}[2K"

    /// Code to end any currently active wrapping.
    private let resetString = "\u{001B}[0m"

    /// Code to make string bold.
    private let boldString = "\u{001B}[1m"

    /// Constructs the instance if the stream is a tty.
    public init?(stream: LocalFileOutputByteStream) {
        // Make sure this file stream is tty.
        guard isatty(fileno(stream.fp)) != 0 else {
            return nil
        }
        width = TerminalController.terminalWidth() ?? 80 // Assume default if we are not able to determine.
        self.stream = stream
    }

    /// Tries to get the terminal width first using COLUMNS env variable and
    /// if that fails ioctl method testing on stdout stream.
    ///
    /// - Returns: Current width of terminal if it was determinable.
    public static func terminalWidth() -> Int? {
        // Try to get from environment.
        if let columns = POSIX.getenv("COLUMNS"), let width = Int(columns) {
            return width
        }

        // Try determining using ioctl.
        var ws = winsize()
        if ioctl(1, UInt(TIOCGWINSZ), &ws) == 0 {
            return Int(ws.ws_col)
        }
        return nil
    }

    /// Flushes the stream.
    public func flush() {
        stream.flush()
    }

    /// Clears the current line and moves the cursor to beginning of the line..
    public func clearLine() {
        stream <<< clearLineString <<< "\r"
        flush()
    }

    /// Moves the cursor y columns up.
    public func moveCursor(y: Int) {
        stream <<< "\u{001B}[\(y)A"
        flush()
    }

    /// Writes a string to the stream.
    public func write(_ string: String, inColor color: Color = .noColor, bold: Bool = false) {
        writeWrapped(string, inColor: color, bold: bold, stream: stream)
        flush()
    }

    /// Inserts a new line character into the stream.
    public func endLine() {
        stream <<< "\n"
        flush()
    }

    /// Wraps the string into the color mentioned.
    public func wrap(_ string: String, inColor color: Color, bold: Bool = false) -> String {
        let stream = BufferedOutputByteStream()
        writeWrapped(string, inColor: color, bold: bold, stream: stream)
        guard let string = stream.bytes.asString else {
            fatalError("Couldn't get string value from stream.")
        }
        return string
    }

    private func writeWrapped(_ string: String, inColor color: Color, bold: Bool = false, stream: OutputByteStream) {
        // Don't wrap if string is empty or color is no color.
        guard !string.isEmpty && color != .noColor else {
            stream <<< string
            return
        }
        stream <<< color.string <<< (bold ? boldString : "") <<< string <<< resetString
    }
}
