/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basics
#if os(macOS)
import class Foundation.Bundle
#endif
import TSCBasic
@_exported import TSCTestSupport
import XCTest

import struct TSCUtility.Version

public func XCTAssertBuilds(
    _ path: AbsolutePath,
    configurations: Set<Configuration> = [.Debug, .Release],
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: EnvironmentVariables? = nil,
    file: StaticString = #file,
    line: UInt = #line
) {
    for conf in configurations {
        XCTAssertNoThrow(
            try executeSwiftBuild(
                path,
                configuration: conf,
                extraArgs: extraArgs,
                Xcc: Xcc,
                Xld: Xld,
                Xswiftc: Xswiftc,
                env: env
            ),
            file: file,
            line: line
        )
    }
}

public func XCTAssertSwiftTest(
    _ path: AbsolutePath,
    env: EnvironmentVariables? = nil,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertNoThrow(
        try SwiftPMProduct.SwiftTest.execute([], packagePath: path, env: env),
        file: file,
        line: line
    )
}

@discardableResult
public func XCTAssertBuildFails(
    _ path: AbsolutePath,
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: EnvironmentVariables? = nil,
    file: StaticString = #file,
    line: UInt = #line
) -> CommandExecutionError? {
    var failure: CommandExecutionError? = nil
    XCTAssertThrowsCommandExecutionError(try executeSwiftBuild(path, Xcc: Xcc, Xld: Xld, Xswiftc: Xswiftc), file: file, line: line) { error in
        failure = error
    }
    return failure
}

public func XCTAssertEqual<T: CustomStringConvertible>(
    _ assignment: [(container: T, version: Version)],
    _ expected: [T: Version],
    file: StaticString = #file,
    line: UInt = #line
) where T: Hashable {
    var actual = [T: Version]()
    for (identifier, binding) in assignment {
        actual[identifier] = binding
    }
    XCTAssertEqual(actual, expected, file: file, line: line)
}

public func XCTAssertThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: CommandExecutionError) -> Void = { _ in }
) {
    XCTAssertThrowsError(try expression(), message(), file: file, line: line) { error in
        guard case SwiftPMProductError.executionFailure(let processError, let stdout, let stderr) = error,
              case ProcessResult.Error.nonZeroExit(let processResult) = processError,
              processResult.exitStatus != .terminated(code: 0) else {
            return XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
        errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
    }
}

public struct CommandExecutionError: Error {
    public let result: ProcessResult
    public let stdout: String
    public let stderr: String
}
