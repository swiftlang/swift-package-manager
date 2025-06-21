//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import TSCTestSupport
import Testing

public func expectThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ errorHandler: (_ error: CommandExecutionError) throws -> Void = { _ in }
) async rethrows {
    let error = await #expect(throws: SwiftPMError.self, sourceLocation: sourceLocation) {
        try await expression()
    }

    guard case .executionFailure(let processError, let stdout, let stderr) = error,
          case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
          processResult.exitStatus != .terminated(code: 0) else {
        Issue.record("Unexpected error type: \(error?.interpolationDescription)", sourceLocation: sourceLocation)
        return
    }
    try errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
}
