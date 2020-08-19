/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCLibc
#if os(Windows)
import MSVCRT
#endif

/// A class to have better control on tty output streams: standard output and standard error.
/// Allows operations like cursor movement and colored text output on tty.
public final class TerminalController {

    /// The type of terminal.
    public enum TerminalType {
        /// The terminal is a TTY.
        case tty

        /// TERM enviornment variable is set to "dumb".
        case dumb

        /// The terminal is a file stream.
        case file
    }

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
    private var stream: OutputByteStream

    /// Width of the terminal.
    public let width: Int

    /// Code to clear the line on a tty.
    private let clearLineString = "\u{001B}[2K"

    /// Code to end any currently active wrapping.
    private let resetString = "\u{001B}[0m"

    /// Code to make string bold.
    private let boldString = "\u{001B}[1m"

    /// Constructs the instance if the stream is a tty.
    public init?(stream: OutputByteStream) {
        let realStream = (stream as? ThreadSafeOutputByteStream)?.stream ?? stream

        // Make sure it is a file stream and it is tty.
        guard let fileStream = realStream as? LocalFileOutputByteStream, TerminalController.isTTY(fileStream) else {
            return nil
        }

        // Determine the terminal width otherwise assume a default.
        if let terminalWidth = TerminalController.terminalWidth(), terminalWidth > 0 {
            width = terminalWidth
        } else {
            width = 80
        }

#if os(Windows)
       // Enable VT100 interpretation
        let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
        var dwMode: DWORD = 0

        guard hOut != INVALID_HANDLE_VALUE else { return nil }
        guard GetConsoleMode(hOut, &dwMode) else { return nil }

        dwMode |= DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING)
        guard SetConsoleMode(hOut, dwMode) else { return nil }
#endif
        self.stream = stream
    }

    /// Checks if passed file stream is tty.
    public static func isTTY(_ stream: LocalFileOutputByteStream) -> Bool {
        return terminalType(stream) == .tty
    }

    /// Computes the terminal type of the stream.
    public static func terminalType(_ stream: LocalFileOutputByteStream) -> TerminalType {
#if os(Windows)
        return _isatty(_fileno(stream.filePointer)) == 0 ? .file : .tty
#else
        if ProcessEnv.vars["TERM"] == "dumb" {
            return .dumb
        }
        let isTTY = isatty(fileno(stream.filePointer)) != 0
        return isTTY ? .tty : .file
#endif
    }

    /// Tries to get the terminal width first using COLUMNS env variable and
    /// if that fails ioctl method testing on stdout stream.
    ///
    /// - Returns: Current width of terminal if it was determinable.
    public static func terminalWidth() -> Int? {
#if os(Windows)
        var csbi: CONSOLE_SCREEN_BUFFER_INFO = CONSOLE_SCREEN_BUFFER_INFO()
        if !GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi) {
          // GetLastError()
          return nil
        }
        return Int(csbi.srWindow.Right - csbi.srWindow.Left) + 1
#else
        // Try to get from environment.
        if let columns = ProcessEnv.vars["COLUMNS"], let width = Int(columns) {
            return width
        }

        // Try determining using ioctl.
        // Following code does not compile on ppc64le well. TIOCGWINSZ is
        // defined in system ioctl.h file which needs to be used. This is
        // a temporary arrangement and needs to be fixed.
#if !arch(powerpc64le)
        var ws = winsize()
        if ioctl(1, UInt(TIOCGWINSZ), &ws) == 0 {
            return Int(ws.ws_col)
        }
#endif
        return nil
#endif
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
    public func moveCursor(up: Int) {
        stream <<< "\u{001B}[\(up)A"
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
        return stream.bytes.description
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
