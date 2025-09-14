/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Testing

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

public func expectFileDoesNotExists(
    at fixturePath: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    let commentPrefix =
        if let comment {
            "\(comment): "
        } else {
            ""
        }
    #expect(
        !localFileSystem.exists(fixturePath),
        "\(commentPrefix)\(fixturePath) does not exist",
        sourceLocation: sourceLocation,
    )
}

public func expectFileIsExecutable(
    at fixturePath: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    let commentPrefix =
        if let comment {
            "\(comment): "
        } else {
            ""
        }
    #expect(
        localFileSystem.isExecutableFile(fixturePath),
        "\(commentPrefix)\(fixturePath) does not exist",
        sourceLocation: sourceLocation,
    )
}

public func expectDirectoryExists(
    at path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.isDirectory(path),
        "Expected directory doesn't exist: \(path)",
        sourceLocation: sourceLocation,
    )
}

public func expectDirectoryDoesNotExist(
    at path: AbsolutePath,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        !localFileSystem.isDirectory(path),
        "Directory exists unexpectedly: \(path)",
        sourceLocation: sourceLocation,
    )
}

/// Expects that the expression throws a CommandExecutionError and passes it to the provided throwing error handler.
/// - Parameters:
///   - expression: The expression expected to throw
///   - message: Optional message for the expectation
///   - sourceLocation: Source location for error reporting
///   - errorHandler: A throwing closure that receives the CommandExecutionError
public func expectThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> Comment = "",
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) throws -> Void = { _ in }
) async rethrows {
    _ = try await _expectThrowsCommandExecutionError(
        { try await expression() },
        { message() },
        sourceLocation: sourceLocation,
        errorHandler
    )
}

/// Expects that the expression throws a CommandExecutionError and passes it to the provided non-throwing error handler.
/// This version can be called without `try` when the error handler doesn't throw.
/// - Parameters:
///   - expression: The expression expected to throw
///   - message: Optional message for the expectation
///   - sourceLocation: Source location for error reporting
///   - errorHandler: A non-throwing closure that receives the CommandExecutionError
public func expectThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> Comment = "",
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) -> Void
) async {
    _ = try? await _expectThrowsCommandExecutionError(
        { try await expression() },
        { message() },
        sourceLocation: sourceLocation
    ) { error in
        errorHandler(error)
        return ()
    }
}

private func _expectThrowsCommandExecutionError<R, T>(
    _ expressionClosure: () async throws -> T,
    _ message: () -> Comment,
    sourceLocation: SourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) throws -> R
) async rethrows -> R? {
    let err = await #expect(throws: SwiftPMError.self, message(), sourceLocation: sourceLocation) {
        try await expressionClosure()
    }

    guard let error = err,
          case .executionFailure(let processError, let stdout, let stderr) = error,
          case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
          processResult.exitStatus != .terminated(code: 0) else {
        Issue.record("Unexpected error type: \(err?.interpolationDescription ?? "<unknown>")", sourceLocation: sourceLocation)
        return nil
    }
    return try errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
}
