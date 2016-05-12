/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import func POSIX.isatty
import libc

public var colorMode = ColorWrap.Mode.Auto 

/// Wrap the text with color.
public enum ColorWrap {

    /// Wrap the given text with provided color for a stream.
    /// Color codes will only be added if and only if:
    ///     stream is TTY && --color=auto
    ///     or
    ///     --color=always
    public static func wrap(_ input: String, with color: Color, for stream: Stream) -> String {
        guard ColorWrap.isAllowed(for: .StdErr) else { return input }
        return input.wrapped(in: color)
    }

    /// Check if color code generation is enabled for this stream.
    public static func isAllowed(for stream: Stream) -> Bool {
        switch colorMode {
        case .Auto: return isTTY(stream)
        case .Never: return false
        case .Always: return true
        }
    }

    /// Color modes supported by `--color` flag
    ///
    /// auto: Use Color codes only when printing to a terminal
    /// always: Always print color codes
    /// never: No color codes at all
    public enum Mode: CustomStringConvertible {
        case Auto, Always, Never

        public init?(_ rawValue: String?) {
            guard let rawValue = rawValue else {
                self = .Auto
                return
            }
            switch rawValue.lowercased() {
            case "auto": self = .Auto
            case "always": self = .Always
            case "never": self = .Never
            default: return nil
            }
        }

        public var description: String {
            switch self {
            case .Auto: return "auto"
            case .Always: return "always"
            case .Never: return "never"
            }
        }
    }

    public enum Color {
        case Red, Blue
    }
}


extension String {
    /// Surround this string with color codes.
    func wrapped(in color: ColorWrap.Color) -> String {
        let ESC = "\u{001B}"
        let CSI = "\(ESC)["

        switch color {
        case .Blue:
            return "\(CSI)34m\(self)\(CSI)0m"
        case .Red:
            return "\(CSI)31m\(self)\(CSI)0m"
        }
    }
}
