/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
import Testing
import Foundation
import class TSCBasic.BufferedOutputByteStream

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

/// An `async`-friendly replacement for `XCTAssertThrowsError`.
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

/// Checks if an output stream contains a specific string, with retry logic for asynchronous writes.
/// - Parameters:
///   - outputStream: The output stream to check
///   - needle: The string to search for in the output stream
///   - timeout: Maximum time to wait for the string to appear (default: 3 seconds)
///   - retryInterval: Time to wait between checks (default: 50 milliseconds)
/// - Returns: True if the string was found within the timeout period
public func waitForOutputStreamToContain(
    _ outputStream: BufferedOutputByteStream,
    _ needle: String,
    timeout: TimeInterval = 3.0,
    retryInterval: TimeInterval = 0.05
) async throws -> Bool {
    let description = outputStream.bytes.description
    if description.contains(needle) {
        return true
    }

    let startTime = Date()
    while Date().timeIntervalSince(startTime) < timeout {
        let description = outputStream.bytes.description
        if description.contains(needle) {
            return true
        }

        try await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
    }

    return outputStream.bytes.description.contains(needle)
}