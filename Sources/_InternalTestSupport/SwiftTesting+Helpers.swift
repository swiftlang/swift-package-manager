//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Testing

private func fileExistsErrorMessage(
    for path: AbsolutePath,
    comment: Comment?
) -> Comment {
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
    return Comment("\(commentPrefix)File '\(path)' does not exist. \(msgSuffix)")
}

public func expectFileExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(
        localFileSystem.exists(path),
        fileExistsErrorMessage(for: path, comment: comment),
        sourceLocation: sourceLocation,
    )
}

public func requireFileExists(
    at path: AbsolutePath,
    _ comment: Comment? = nil,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    try #require(
        localFileSystem.exists(path),
        fileExistsErrorMessage(for: path, comment: comment),
        sourceLocation: sourceLocation,
    )
}

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
        !localFileSystem.exists(path),
        "\(commentPrefix)File: '\(path)' was not expected to exist, but does.\(msgSuffix))",
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
        "\(commentPrefix)File '\(fixturePath)' expected to be executable, but is not.",
        sourceLocation: sourceLocation,
    )
}

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

/// Expects a directory (recursively) contains a file.
package func expectDirectoryContainsFile(
    dir: AbsolutePath,
    filename: String,
    sourceLocation: SourceLocation = #_sourceLocation,
) {
    do {
        for entry in try walk(dir) {
            if entry.basename == filename { return }
        }
    } catch {
        Issue.record("Failed with error \(error)", sourceLocation: sourceLocation)
    }
    Issue.record("Directory \(dir) does not contain \(filename)", sourceLocation: sourceLocation)
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
