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
