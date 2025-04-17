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

/// Emits errors, warnings, and remarks to be shown as a result of running the
/// plugin. After emitting one or more errors, the plugin should return a
/// non-zero exit code.
public struct Diagnostics {

    /// Severity of the diagnostic.
    public enum Severity: String, Encodable {
        case error, warning, remark
    }
    
    /// Emits an error with a specified severity and message, and optional file path and line number.
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
    public static func error(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.error, message, file: file, line: line)
    }

    /// Emits a warning with the specified message, and optional file path and line number.
    public static func warning(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.warning, message, file: file, line: line)
    }

    /// Emits a remark with the specified message, and optional file path and line number.
    public static func remark(_ message: String, file: String? = #file, line: Int? = #line) {
        self.emit(.remark, message, file: file, line: line)
    }

    /// Emits a progress message
    public static func progress(_ message: String) {
        try? pluginHostConnection.sendMessage(.emitProgress(message: message))
    }
}
