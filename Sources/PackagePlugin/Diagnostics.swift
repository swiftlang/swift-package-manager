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

/// Emits messages the system shows as a result of running the plugin.
///
/// > Note: If the plugin emits one or more errors, it should return a
/// > non-zero exit code.
public struct Diagnostics {

    /// Severity of the diagnostic message.
    public enum Severity: String, Encodable {
        /// The diagnostic message is an error.
        case error
        /// The diagnostic message is a warning.
        case warning
        /// The diagnostic message is a remark.
        case remark
    }
    
    /// Emits a message with a specified severity, and optional file path and line number.
    ///
    /// - Parameters:
    ///   - severity: The severity of the message.
    ///   - description: The message to display.
    ///   - file: The source file to which the message relates.
    ///   - line: The line number in the source file to which the message relates.
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

    /// Emits an error with the specified message, and optional file path and line number.
    ///
    /// - Parameters:
    ///   - message: The text of the error.
    ///   - file: The source file to which the error relates.
    ///   - line: The line number in the source file to which the error relates.
    public static func error(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.error, message, file: file, line: line)
    }

    /// Emits a warning with the specified message, and optional file path and line number.
    ///
    /// - Parameters:
    ///   - message: The text of the warning.
    ///   - file: The source file to which the warning relates.
    ///   - line: The line number in the source file to which the warning relates.
    public static func warning(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.warning, message, file: file, line: line)
    }

    /// Emits a remark with the specified message, and optional file path and line number.
    ///
    /// - Parameters:
    ///   - message: The text of the remark.
    ///   - file: The source file to which the remark relates.
    ///   - line: The line number in the source file to which the remark relates.
    public static func remark(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.remark, message, file: file, line: line)
    }

    /// Emits a progress message.
    ///
    /// - Parameter message: The text of the progress update.
    public static func progress(_ message: String) {
        try? pluginHostConnection.sendMessage(.emitProgress(message: message))
    }
}
