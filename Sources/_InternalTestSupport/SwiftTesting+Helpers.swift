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
public func expectAsyncThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> Comment = "",
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        Issue.record(message(), sourceLocation: sourceLocation)
    } catch {
        errorHandler(error)
    }
}
