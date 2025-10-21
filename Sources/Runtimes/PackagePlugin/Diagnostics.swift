//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Emits errors, warnings, and remarks to show as a result of running the
/// plugin.
///
/// After emitting one or more errors, a plugin should return a
/// non-zero exit code.
public struct Diagnostics {

    /// The severity of the diagnostic.
    public enum Severity: String, Encodable {
        case error, warning, remark
    }
    
    /// Emits an error with a specified severity and message, and optional file path and line number.
    /// - Parameters:
    ///   - severity: The severity of the diagnostic.
    ///   - description: The description of the diagnostic.
    ///   - file: The file responsible for the diagnostic, that defaults to `#file`.
    ///   - line: The line responsible for the diagnostic, that defaults to `#line`.
    public static func emit(_ severity: Severity, _ description: String, file: String? = #file, line: Int? = #line) {
        let message: PluginToHostMessage
        switch severity {
        case .error:
            message = .emitDiagnostic(severity: .error, message: description, file: file, line: line)
        case .warning:
            message = .emitDiagnostic(severity: .warning, message: description, file: file, line: line)
        case .remark:
            message = .emitDiagnostic(severity: .remark, message: description, file: file, line: line)
        }
        // FIXME: Handle problems sending the message.
        try? pluginHostConnection.sendMessage(message)
    }

    /// Emits an error with the message you specify.
    /// - Parameters:
    ///   - message: The description of the error.
    ///   - file: The file responsible for the diagnostic, that defaults to `#file`.
    ///   - line: The line responsible for the diagnostic, that defaults to `#line`.
    public static func error(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.error, message, file: file, line: line)
    }

    /// Emits a warning with the message you specify.
    /// - Parameters:
    ///   - message: The description of the warning.
    ///   - file: The file responsible for the diagnostic, that defaults to `#file`.
    ///   - line: The line responsible for the diagnostic, that defaults to `#line`.
    public static func warning(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.warning, message, file: file, line: line)
    }

    /// Emits a remark with the message you specify.
    /// - Parameters:
    ///   - message: The description of the remark.
    ///   - file: The file responsible for the diagnostic, that defaults to `#file`.
    ///   - line: The line responsible for the diagnostic, that defaults to `#line`.
    public static func remark(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.remark, message, file: file, line: line)
    }

    /// Emits a progress message.
    /// - Parameter message: The description of the progress.
    public static func progress(_ message: String) {
        try? pluginHostConnection.sendMessage(.emitProgress(message: message))
    }
}
