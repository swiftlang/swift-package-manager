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
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.exists(path),
        "Files '\(path)' does not exist.",
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
    let commentPrefix =
        if let comment {
            "\(comment): "
        } else {
            ""
        }
    let msgSuffix: String
    do {
        msgSuffix = try "Directory contents: \(localFileSystem.getDirectoryContents(path.parentDirectory))"
    } catch {
        msgSuffix = ""
    }
    #expect(
        localFileSystem.exists(path),
        "\(commentPrefix)File '\(path)' does not exist. \(msgSuffix)",
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
    let commentPrefix =
        if let comment {
            "\(comment): "
        } else {
            ""
        }
    #expect(
        localFileSystem.isExecutableFile(fixturePath),
        "\(commentPrefix)File '\(fixturePath)' expected to be executable, but is not.",
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
    sourceLocation: SourceLocation = #_sourceLocation,
) {
let msgSuffix: String
    do {
        msgSuffix = try "Directory contents: \(localFileSystem.getDirectoryContents(path))"
    } catch {
        msgSuffix = ""
    }
    #expect(
        localFileSystem.isDirectory(path),
        "Expected directory doesn't exist: '\(path)'. \(msgSuffix)",
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
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    let msgSuffix: String
    do {
        msgSuffix = try "Directory contents: \(localFileSystem.getDirectoryContents(path))"
    } catch {
        msgSuffix = ""
    }
    #expect(
        !localFileSystem.isDirectory(path),
        "Directory exists unexpectedly: '\(path)'.\(msgSuffix)",
        sourceLocation: sourceLocation,
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
            processResult.exitStatus != .terminated(code: 0)
        else {
            Issue.record("Unexpected error type: \(error.interpolationDescription)", sourceLocation: sourceLocation)
            return
        }
        errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
    }
}

/// An async-friendly replacement for `XCTAssertThrowsError` that verifies an expression throws an error.
///
/// - Parameters:
///   - expression: The expression to evaluate that should throw an error.
///   - message: An optional failure message to display if the expression doesn't throw.
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
        Issue.record(
            message() ?? "Expected an error, which did not occur.",
            sourceLocation: sourceLocation,
        )
    } catch {
        errorHandler(error)
    }
}
