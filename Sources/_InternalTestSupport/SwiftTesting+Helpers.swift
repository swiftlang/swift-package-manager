/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Testing
import TSCTestSupport

// MARK: File Helpers

/// Verifies that a file exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for file existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectFileExists(
    at path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.exists(path),
        "Files '\(path)' does not exist.",
        sourceLocation: sourceLocation,
    )
}

/// Verifies that no file or directory exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for non-existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectNoSuchPath(
    _ path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        !localFileSystem.exists(path),
        "Expected no such path '\(path)'",
        sourceLocation: sourceLocation
    )
}

/// Verifies that a directory exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for directory existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectDirectoryExists(
    _ path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        localFileSystem.isDirectory(path),
        "Expected directory at '\(path)'",
        sourceLocation: sourceLocation
    )
}

// MARK: Error Helpers

/// Verifies that an expression throws a `CommandExecutionError`.
///
/// - Parameters:
///   - expression: The expression to evaluate.
///   - message: An optional description of the failure.
///   - sourceLocation: The source location where the expectation is made.
///   - errorHandler: A closure that's called with the error if the expression throws.
public func expectThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> Comment = "",
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) -> Void = { _ in }
) async {
    await expectAsyncThrowsError(try await expression(), message(), sourceLocation: sourceLocation) { error in
        guard case SwiftPMError.executionFailure(let processError, let stdout, let stderr) = error,
              case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
              processResult.exitStatus != .terminated(code: 0) else {
            Issue.record("Unexpected error type: \(error.interpolationDescription)", sourceLocation: sourceLocation)
            return
        }
        errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
    }
}

/// An `async`-friendly replacement for `XCTAssertThrowsError`.
///
/// - Parameters:
///   - expression: The expression to evaluate.
///   - message: An optional description of the failure.
///   - sourceLocation: The source location where the expectation is made.
///   - errorHandler: A closure that's called with the error if the expression throws.
public func expectAsyncThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        Issue.record(message() ?? "Expected an error, which did not not.", sourceLocation: sourceLocation)
    } catch {
        errorHandler(error)
    }
}

