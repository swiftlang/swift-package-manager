/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// Emits errors, warnings, and remarks to be shown as a result of running the
/// extension. After emitting one or more errors, the extension should return a
/// non-zero exit code.
public final class DiagnosticsEmitter {
    // This prevents a DiagnosticsEmitter from being instantiated by the script.
    internal init() {}

    /// Emits an error with the specified message and optional file path and line number..
    public func emit(error message: String, file: Path? = nil, line: Int? = nil) {
        output.diagnostics.append(Diagnostic(severity: .error, message: message, file: file, line: line))
    }

    /// Emits a warning with the specified message and optional file path and line number..
    public func emit(warning message: String, file: Path? = nil, line: Int? = nil) {
        output.diagnostics.append(Diagnostic(severity: .warning, message: message, file: file, line: line))
    }

    /// Emits a remark with the specified message and optional file path and line number..
    public func emit(remark message: String, file: Path? = nil, line: Int? = nil) {
        output.diagnostics.append(Diagnostic(severity: .remark, message: message, file: file, line: line))
    }
}
