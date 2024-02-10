//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import class TSCBasic.BufferedOutputByteStream
import protocol TSCBasic.WritableByteStream
import TSCLibc
#if os(Windows)
import CRT
#endif

struct TerminalController {
    var stream: WritableByteStream
    var buffer: TerminalOutputBuffer
    var coloring: TerminalColoring

    init(stream: WritableByteStream, coloring: TerminalColoring) {
        // This feels like a very bad place to run this side-effect
        Self.enableVT100Interpretation()
        self.stream = stream
        self.buffer = .init()
        self.coloring = coloring
    }

    /// Writes a string to the stream.
    mutating func write(_ text: String) {
        self.buffer.write(text.utf8)
    }

    /// Writes bytes to the stream.
    mutating func write(_ bytes: some Collection<UInt8>) {
        self.buffer.write(bytes)
    }

    mutating func newLine() {
        self.buffer.write("\n")
    }

    mutating func carriageReturn() {
        self.buffer.write("\r")
    }

    mutating func flush() {
        self.buffer.flush { bytes in
            self.stream.write(bytes)
            self.stream.flush()
        }
    }
}

extension TerminalController {
    static func enableVT100Interpretation() {
#if os(Windows)
        let hOut = GetStdHandle(STD_OUTPUT_HANDLE)
        var dwMode: DWORD = 0

        guard hOut != INVALID_HANDLE_VALUE else { return nil }
        guard GetConsoleMode(hOut, &dwMode) else { return nil }

        dwMode |= DWORD(ENABLE_VIRTUAL_TERMINAL_PROCESSING)
        guard SetConsoleMode(hOut, dwMode) else { return nil }
#endif
    }

    /// Tries to get the terminal width first using COLUMNS env variable and
    /// if that fails ioctl method testing on stdout stream.
    ///
    /// - Returns: Current width of terminal if it was determinable.
    static func width() -> Int? {
#if os(Windows)
        var csbi: CONSOLE_SCREEN_BUFFER_INFO = CONSOLE_SCREEN_BUFFER_INFO()
        if !GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi) {
          // GetLastError()
          return nil
        }
        return Int(csbi.srWindow.Right - csbi.srWindow.Left) + 1
#else
        // Try to get from environment.
        if let columns = Environment.current["COLUMNS"], let width = Int(columns) {
            return width
        }

        // Try determining using ioctl.
        // Following code does not compile on ppc64le well. TIOCGWINSZ is
        // defined in system ioctl.h file which needs to be used. This is
        // a temporary arrangement and needs to be fixed.
#if !arch(powerpc64le)
        var ws = winsize()
#if os(OpenBSD)
        let tiocgwinsz = 0x40087468
        let err = ioctl(1, UInt(tiocgwinsz), &ws)
#else
        let err = ioctl(1, UInt(TIOCGWINSZ), &ws)
#endif
        if err == 0 {
            return Int(ws.ws_col)
        }
#endif
        return nil
#endif
    }
}

extension TerminalController {
    /// ESC character.
    private static let escape = "\u{001B}["

    mutating func moveCursorUp(cells: Int) { self.buffer.write("\(Self.escape)\(cells)A") }

    mutating func moveCursorDown(cells: Int) { self.buffer.write("\(Self.escape)\(cells)B") }

    mutating func moveCursorForward(cells: Int) { self.buffer.write("\(Self.escape)\(cells)C") }

    mutating func moveCursorBackward(cells: Int) { self.buffer.write("\(Self.escape)\(cells)D") }

    mutating func moveCursorNext(lines: Int) { self.buffer.write("\(Self.escape)\(lines)E") }

    mutating func moveCursorPrevious(lines: Int) { self.buffer.write("\(Self.escape)\(lines)F") }

    mutating func positionCursor(column: Int) { self.buffer.write("\(Self.escape)\(column)G") }

    mutating func positionCursor(row: Int, column: Int) { self.buffer.write("\(Self.escape)\(row);\(column)H") }

    mutating func saveCursorPosition() { self.buffer.write("\(Self.escape)s") }

    mutating func restoreCursorPosition() { self.buffer.write("\(Self.escape)u") }

    mutating func hideCursor() { self.buffer.write("\(Self.escape)?25l") }

    mutating func showCursor() { self.buffer.write("\(Self.escape)?25h") }

    enum EraseControl: Int {
        /// Clear from cursor to end
        case fromCursor = 0
        /// Clear from cursor to beginning
        case toCursor = 1
        /// Clear entire
        case entire = 2
    }

    /// ANSI escape code for erasing content in the current display.
    mutating func eraseDisplay(_ kind: EraseControl) {
        self.buffer.write("\(Self.escape)\(kind.rawValue)J")
    }

    /// ANSI escape code for erasing content in the current line.
    mutating func eraseLine(_ kind: EraseControl) {
        self.buffer.write("\(Self.escape)\(kind.rawValue)K")
    }

    mutating func text(styles: ANSITextStyle...) {
        precondition(!styles.isEmpty)
        guard self.coloring != .noColors else { return }
        self.buffer.write("\(Self.escape)\(styles[0].rawValue)")
        for style in styles.dropFirst() {
            self.buffer.write(";\(style.rawValue)")
        }
        self.buffer.write("m")
    }
}

struct ANSITextStyle {
    var rawValue: String
}

/// Documentation from Wikipedia: https://en.wikipedia.org/wiki/ANSI_escape_code
extension ANSITextStyle {
    enum Color: UInt8 {
        case black = 0
        case red = 1
        case green = 2
        case yellow = 3
        case blue = 4
        case magenta = 5
        case cyan = 6
        case white = 7
    }

    /// Reset or normal
    ///
    /// All attributes become turned off.
    static var reset: Self { .init(rawValue: "0") }

    /// Bold or increased intensity
    ///
    /// As with faint, the color change is a PC (SCO / CGA) invention.
    static var bold: Self { .init(rawValue: "1") }

    /// Faint, decreased intensity, or dim
    ///
    /// May be implemented as a light font weight like bold.
    static var faint: Self { .init(rawValue: "2") }

    /// Italic
    ///
    /// Not widely supported. Sometimes treated as inverse or blink.
    static var italic: Self { .init(rawValue: "3") }

    /// Underline
    ///
    /// Style extensions exist for Kitty, VTE, mintty, iTerm2, and Konsole.
    static var underline: Self { .init(rawValue: "4") }

    /// Slow blink
    ///
    /// Sets blinking to less than 150 times per minute.
    static var blink: Self { .init(rawValue: "5") }

    /// Rapid blink
    ///
    /// MS-DOS ANSI.SYS, 150+ per minute; not widely supported.
    static var rapidBlink: Self { .init(rawValue: "6") }

    /// Reverse video or invert
    ///
    /// Swap foreground and background colors; inconsistent emulation.
    static var inverted: Self { .init(rawValue: "7") }

    /// Conceal or hide
    ///
    /// Not widely supported.
    static var hidden: Self { .init(rawValue: "8") }

    /// Crossed-out, or strike
    ///
    /// Characters legible but marked as if for deletion. Not supported in
    /// Terminal.app.
    static var strikeThrough: Self { .init(rawValue: "9") }

    /// Primary (default) font
    static var primaryFont: Self { .init(rawValue: "10") }

    /// Alternative font
    ///
    /// Select alternative font from 1 to 9.
    static func alternateFont(_ font: Int) -> Self {
        precondition(font >= 1 && font <= 9)
        return .init(rawValue: "\(10 + UInt8(font))")
    }

    /// Fraktur (Gothic)
    ///
    /// Rarely supported.
    static var fraktur: Self { .init(rawValue: "20") }

    /// Doubly underlined; or: not bold
    ///
    /// Double-underline per ECMA-48: 8.3.117 but instead disables bold
    /// intensity on several terminals, including in the Linux kernel's console
    /// before version 4.17.
    static var doubleUnderline: Self { .init(rawValue: "21") }

    /// Normal intensity
    ///
    /// Neither bold nor faint; color changes where intensity is implemented as
    /// such.
    static var normalWeight: Self { .init(rawValue: "22") }

    /// Neither italic, nor bold
    static var notItalicNorBold: Self { .init(rawValue: "23") }

    /// Not underlined
    ///
    /// Neither singly nor doubly underlined.
    static var notUnderlined: Self { .init(rawValue: "24") }

    /// Not blinking
    ///
    /// Turn blinking off.
    static var notBlinking: Self { .init(rawValue: "25") }

    /// Proportional spacing
    ///
    /// ITU T.61 and T.416, not known to be used on terminals
    static var proportionalSpacing: Self { .init(rawValue: "26") }

    /// Not reversed
    static var notReversed: Self { .init(rawValue: "27") }

    /// Reveal
    ///
    /// Not concealed
    static var notHidden: Self { .init(rawValue: "28") }

    /// Not crossed out
    static var notStrikethrough: Self { .init(rawValue: "29") }

    /// Set foreground color
    static func foregroundColor(_ color: Color) -> Self {
        .init(rawValue: "\(30 + color.rawValue)")
    }

    /// Set foreground color
    ///
    /// Next arguments are 5;n or 2;r;g;b
    static func foregroundColor(red: UInt8, green: UInt8, blue: UInt8) -> Self {
        .init(rawValue: "38;2;\(red);\(green);\(blue)")
    }

    /// Default foreground color
    ///
    /// Implementation defined (according to standard)
    static var defaultForegroundColor: Self { .init(rawValue: "39") }

    /// Set background color
    static func backgroundColor(_ color: Color) -> Self {
        .init(rawValue: "\(40 + color.rawValue)")
    }

    /// Set background color
    ///
    /// Next arguments are 5;n or 2;r;g;b
    static func backgroundColor(red: UInt8, green: UInt8, blue: UInt8) -> Self {
        .init(rawValue: "48;2;\(red);\(green);\(blue)")
    }

    /// Default background color
    ///
    /// Implementation defined (according to standard)
    static var defaultBackgroundColor: Self { .init(rawValue: "49") }

    /// Disable proportional spacing
    ///
    /// T.61 and T.416
    static var notProportionalSpacing: Self { .init(rawValue: "50") }

    /// Framed
    ///
    /// Implemented as "emoji variation selector" in mintty.
    static var framed: Self { .init(rawValue: "51") }

    /// Encircled
    static var encircled: Self { .init(rawValue: "52") }

    /// Overlined
    ///
    /// Not supported in Terminal.app
    static var overlined: Self { .init(rawValue: "53") }

    /// Neither framed nor encircled
    static var notFramedNorEncircled: Self { .init(rawValue: "54") }

    /// Not overlined
    static var notOverlined: Self { .init(rawValue: "55") }

    /// Set underline color
    ///
    /// Not in standard; implemented in Kitty, VTE, mintty, and iTerm2.
    /// Next arguments are 5;n or 2;r;g;b.
    static func underlineColor() -> Self { .init(rawValue: "58") }

    /// Default underline color
    ///
    /// Not in standard; implemented in Kitty, VTE, mintty, and iTerm2.
    static var defaultUnderlineColor: Self { .init(rawValue: "59") }

    /// Ideogram underline or right side line
    ///
    /// Rarely supported
    static var ideogramUnderline: Self { .init(rawValue: "60") }

    /// Ideogram double underline, or double line on the right side
    static var ideogramDoubleUnderline: Self { .init(rawValue: "61") }

    /// Ideogram overline or left side line
    static var ideogramOverline: Self { .init(rawValue: "62") }

    /// Ideogram double overline, or double line on the left side
    static var ideogramDoubleOverline: Self { .init(rawValue: "63") }

    /// Ideogram stress marking
    static var ideogramStressMarking: Self { .init(rawValue: "64") }

    /// No ideogram attributes
    ///
    /// Reset the effects of all of 60 - 64
    static var defaultIdeogram: Self { .init(rawValue: "65") }

    /// Superscript
    ///
    /// Implemented only in mintty
    static var superscript: Self { .init(rawValue: "73") }

    /// Subscript
    static var `subscript`: Self { .init(rawValue: "74") }

    /// Neither superscript nor subscript
    static var defaultScript: Self { .init(rawValue: "75") }

    /// Set bright foreground color
    ///
    /// Not in standard; originally implemented by aixterm
    static func brightForegroundColor(_ color: Color) -> Self {
        .init(rawValue: "\(90 + color.rawValue)")
    }

    /// Set bright background color
    static func brightBackgroundColor(_ color: Color) -> Self {
        .init(rawValue: "\(100 + color.rawValue)")
    }
}
