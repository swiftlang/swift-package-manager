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

import protocol TSCBasic.WritableByteStream

public enum TerminalColoring {
    /// Support for no colors.
    case noColors
    /// Support for 8 colors.
    ///
    /// Colors: black, red, green, yellow, blue, magenta, cyan, white.
    case _8
    /// Support for 16 colors.
    ///
    /// Colors: standard and bright variants of ``Color._8`` colors.
    case _16
    /// Support for 88 colors.
    ///
    /// Colors: ``Colors._16`` colors, 4x4x4 color cube, and 8 grayscale
    /// colors.
    case _88
    /// Support for 256 colors.
    ///
    /// Colors: ``Colors._16`` colors, 6x6x6 color cube, and 18 grayscale
    /// colors.
    case _256
    /// Support for 16 million colors.
    ///
    /// Colors: all combinations of 8 bit red, green, blue colors.
    case _16m
}

extension TerminalCapabilities {
    static func coloring(
        stream: WritableByteStream,
        environment env: Environment
    ) -> TerminalColoring? {
        // Explicitly disabled colors via CLICOLORS == 0
        if env.cliColor == false { return .noColors }
        // Explicitly disabled colors via NO_COLORS != nil
        if env.noColor { return .noColors }
        // Implicitly disabled colors because Xcode terminal cannot render them.
        if env.runningInXcode { return .noColors }
        // Disabled colors because output stream is not a tty, CI == nil,
        // and CLICOLOR_FORCE == nil.
        // FIXME: dont use stream.isTTY
        guard stream.isTTY || env.runningInCI || env.cliColorForce else {
            return .noColors
        }
        // Determine color support first by consulting COLORTERM which can
        // enable true color (16 million color) support, then checking TERM
        // which can enable 256, 16, or 8 colors.
        return env.colorTerm ?? env.termColoring
    }
}

extension Environment {
    /// Whether the [`"CLICOLOR"`](https://bixense.com/clicolors/) environment
    /// variable is enabled, disabled, or undefined.
    ///
    /// If `true`, colors should be used if the underlying output stream
    /// supports it.` If `false`, colors should not be used.
    ///
    /// - Returns: `nil` if the `"CLICOLOR"` environment variable is undefined,
    ///   `true` if the `"CLICOLOR"` is defined to a non `"0"` value, `false`
    ///   otherwise.
    var cliColor: Bool? {
        self["CLICOLOR"].map { $0 != "0" }
    }

    /// Whether the [`"CLICOLOR_FORCE"`](https://bixense.com/clicolors/)
    /// environment variable is enabled or not.
    ///
    /// If `true`, colors should be always be used.
    ///
    /// - Returns: `true` if the `"CLICOLOR_FORCE"` environment variable is
    ///   defined, `false` otherwise.
    var cliColorForce: Bool {
        self["CLICOLOR_FORCE"] != nil
    }

    /// Whether the [`"NO_COLOR"`](https://no-color.org/) environment variable
    /// is enabled or not.
    ///
    /// If `true`, colors should not be used.
    ///
    /// - Returns: `true` if the `"NO_COLOR"` environment variable is defined,
    ///   `false` otherwise.
    var noColor: Bool {
        self["NO_COLOR"] != nil
    }

    /// The coloring enabled by the `"TERM"` environment variable.
    var termColoring: TerminalColoring? {
        switch self["TERM"] {
        case "dumb": nil
        case "xterm": ._8
        case "xterm-16color": ._16
        case "xterm-256color": ._256
        default: nil
        }
    }

    /// The coloring enabled by the
    /// [`"COLORTERM"`](https://github.com/termstandard/colors) environment
    /// variable.
    var colorTerm: TerminalColoring? {
        switch self["COLORTERM"] {
        case "truecolor", "24bit": ._16m
        default: nil
        }
    }

    /// Whether the current process is running in CI.
    ///
    /// If `true`, colors can be used even if the output stream is not a tty.
    ///
    /// - Returns: `true` if the `"CI"` environment variable is defined, `false`
    ///   otherwise.
    var runningInCI: Bool {
        self["CI"] != nil
    }

    /// Whether the current process is running in Xcode.
    ///
    /// If `true`, colors should not be used.
    ///
    /// - Returns: `true` if the `"XPC_SERVICE_NAME"` environment variable
    ///   includes `"com.apple.dt.xcode"`, `false` otherwise.
    var runningInXcode: Bool {
        self["XPC_SERVICE_NAME"]?.contains("com.apple.dt.xcode") ?? false
    }
}
