/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Testing

// MARK: File System Helpers

/// Verifies that a file exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for file existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectFileExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.exists(path),
        wrapMessage(
            "Files '\(path)' does not exist.",
            comment: comment,
            directoryPath: path.parentDirectory
        ),
        sourceLocation: sourceLocation,
    )
}

/// Requires that a file exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for file existence.
///   - sourceLocation: The source location where the expectation is made.
public func requireFileExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    try #require(
        localFileSystem.exists(path),
        wrapMessage(
            "Files '\(path)' does not exist.",
            comment: comment,
            directoryPath: path.parentDirectory
        ),
        sourceLocation: sourceLocation,
    )
}

/// Verifies that a file does not exist at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for file non-existence.
///   - comment: An optional comment to include in the failure message.
///   - sourceLocation: The source location where the expectation is made.
public func expectFileDoesNotExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        !localFileSystem.exists(path),
        wrapMessage(
            "File: '\(path)' was not expected to exist, but does.",
            comment: comment,
            directoryPath: path.parentDirectory
        ),
        sourceLocation: sourceLocation,
    )
}

/// Verifies that a file exists and is executable at the specified path.
///
/// - Parameters:
///   - fixturePath: The absolute path to check for executable file existence.
///   - comment: An optional comment to include in the failure message.
///   - sourceLocation: The source location where the expectation is made.
public func expectFileIsExecutable(
    at fixturePath: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.isExecutableFile(fixturePath),
        wrapMessage("File '\(fixturePath)' expected to be executable, but is not.", comment: comment),
        sourceLocation: sourceLocation,
    )
}

/// Verifies that a directory exists at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for directory existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectDirectoryExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.isDirectory(path),
        wrapMessage("Expected directory doesn't exist: '\(path)'", comment: comment, directoryPath: path),
        sourceLocation: sourceLocation,
    )
}

/// Verifies that a directory does not exist at the specified path.
///
/// - Parameters:
///   - path: The absolute path to check for directory non-existence.
///   - sourceLocation: The source location where the expectation is made.
public func expectDirectoryDoesNotExist(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        !localFileSystem.isDirectory(path),
        wrapMessage("Directory exists unexpectedly: '\(path)'", comment: comment, directoryPath: path),
        sourceLocation: sourceLocation,
    )
}

/// Wraps a message with an optional comment prefix and directory contents suffix.
///
/// - Parameters:
///   - message: The base message to wrap.
///   - comment: An optional comment to prefix the message with.
///   - directoryPath: An optional path to a folder whose contents will be appended to the message.
/// - Returns: The formatted message with prefix and suffix.
private func wrapMessage(
    _ message: Comment,
    comment: Comment? = nil,
    directoryPath: AbsolutePath? = nil
) -> Comment {
    let commentPrefix =
        if let comment {
            "\(comment): "
        } else {
            ""
        }

    var msgSuffix = ""
    if let directoryPath {
        do {
            msgSuffix = try " Directory contents: \(localFileSystem.getDirectoryContents(directoryPath))"
        } catch {
            // Silently ignore errors when getting directory contents
        }
    }

    return "\(commentPrefix)\(message)\(msgSuffix)"
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
    _ = try await _expectThrowsCommandExecutionError(try await expression(), message(), sourceLocation, errorHandler)
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
    _ = try? await _expectThrowsCommandExecutionError(try await expression(), message(), sourceLocation) { error in
        errorHandler(error)
        return ()
    }
}

private func _expectThrowsCommandExecutionError<R, T>(
    _ expressionClosure: @autoclosure  () async throws -> T,
    _ message: @autoclosure () -> Comment,
    _ sourceLocation: SourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) throws -> R
) async rethrows -> R? {
    // Older toolchains don't have https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0006-return-errors-from-expect-throws.md
    // This can be removed once the CI smoke jobs build with 6.2.
    var err: SwiftPMError?
    await #expect(throws: SwiftPMError.self, message(), sourceLocation: sourceLocation) {
        do {
            let _ = try await expressionClosure()
        } catch {
            err = error as? SwiftPMError
            throw error
        }
    }

    guard let error = err,
          case .executionFailure(let processError, let stdout, let stderr) = error,
          case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
          processResult.exitStatus != .terminated(code: 0) else {
        Issue.record("Unexpected error type: \(err?.interpolationDescription ?? "<unknown>")", sourceLocation: sourceLocation)
        return Optional<R>.none
    }
    return try errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
}
