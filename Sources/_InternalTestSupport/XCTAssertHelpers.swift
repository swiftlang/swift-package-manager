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

import class Foundation.ProcessInfo
import Basics
#if os(macOS)
import class Foundation.Bundle
#endif
import SPMBuildCore
import enum PackageModel.BuildConfiguration
import TSCTestSupport
import XCTest

import struct Basics.AsyncProcessResult

import struct TSCUtility.Version

@_exported import func TSCTestSupport.XCTAssertMatch
@_exported import func TSCTestSupport.XCTAssertNoMatch
@_exported import func TSCTestSupport.XCTAssertResultSuccess
@_exported import func TSCTestSupport.XCTAssertThrows

public func XCTAssertFileExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    TSCTestSupport.XCTAssertFileExists(TSCAbsolutePath(path), file: file, line: line)
}

public func XCTAssertDirectoryExists(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    TSCTestSupport.XCTAssertDirectoryExists(TSCAbsolutePath(path), file: file, line: line)
}

public func XCTAssertNoSuchPath(_ path: AbsolutePath, file: StaticString = #file, line: UInt = #line) {
    TSCTestSupport.XCTAssertNoSuchPath(TSCAbsolutePath(path), file: file, line: line)
}


public func XCTAssertEqual<T:Equatable, U:Equatable> (_ lhs:(T,U), _ rhs:(T,U), file: StaticString = #file, line: UInt = #line) {
    TSCTestSupport.XCTAssertEqual(lhs, rhs, file: file, line: line)
}

public func XCTSkipIfPlatformCI(because reason: String? = nil, file: StaticString = #filePath, line: UInt = #line) throws {
    // TODO: is this actually the right variable now?
    if CiEnvironment.runningInSmokeTestPipeline {
        let failureCause = reason ?? "Skipping because the test is being run on CI"
        throw XCTSkip(failureCause, file: file, line: line)
    }
}

public func XCTSkipIfselfHostedCI(because reason: String, file: StaticString = #filePath, line: UInt = #line) throws {
    // TODO: is this actually the right variable now?
    if CiEnvironment.runningInSelfHostedPipeline {
        throw XCTSkip(reason, file: file, line: line)
    }
}

public func XCTSkipOnWindows(because reason: String? = nil, skipPlatformCi: Bool = false, skipSelfHostedCI: Bool = false , file: StaticString = #filePath, line: UInt = #line) throws {
    #if os(Windows)
    let failureCause: String
    if let reason {
        failureCause = " because \(reason.description)"
    } else {
        failureCause = ""
    }
    if (skipPlatformCi) {
        try XCTSkipIfPlatformCI(because: "Test is run in Platform CI.  Skipping\(failureCause)", file: file, line: line)
    }

    if (skipSelfHostedCI) {
        try XCTSkipIfselfHostedCI(because: "Test is run in Self hosted CI.  Skipping\(failureCause)", file: file, line: line)
    }

    if (!skipPlatformCi && !skipSelfHostedCI) {
        throw XCTSkip("Skipping test\(failureCause)", file: file, line: line)
    }
    #endif
}

public func _requiresTools(_ executable: String) throws {
    func getAsyncProcessArgs(_ executable: String) -> [String] {
        #if os(Windows)
            let args = ["cmd.exe", "/c", "where.exe", executable]
        #else
            let args = ["which", executable]
        #endif
        return args
    }
    try AsyncProcess.checkNonZeroExit(arguments: getAsyncProcessArgs(executable))
}
public func XCTRequires(
    executable: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {

    do {
        try _requiresTools(executable)
    } catch (let AsyncProcessResult.Error.nonZeroExit(result)) {
        throw XCTSkip(
            "Skipping as tool \(executable) is not found in the path. (\(result.description))")
    }
}

public func XCTSkipIfCompilerLessThan6_2() throws {
    #if compiler(>=6.2)
    #else
        throw XCTSkip("Skipping as compiler version is less thann 6.2")
    #endif
}

/// An `async`-friendly replacement for `XCTAssertThrowsError`.
public func XCTAssertAsyncThrowsError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

package func XCTAssertAsyncNoThrow<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
    } catch {
        XCTAssertNoThrow(try { throw error }(), message(), file: file, line: line)
    }
}

public func XCTAssertBuilds(
    _ path: AbsolutePath,
    configurations: Set<BuildConfiguration> = [.debug, .release],
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    file: StaticString = #file,
    line: UInt = #line,
    buildSystem: BuildSystemProvider.Kind,
) async {
    for conf in configurations {
        await XCTAssertAsyncNoThrow(
            try await executeSwiftBuild(
                path,
                configuration: conf,
                extraArgs: extraArgs,
                Xcc: Xcc,
                Xld: Xld,
                Xswiftc: Xswiftc,
                env: env,
                buildSystem: buildSystem
            ),
            file: file,
            line: line
        )
    }
}

public func XCTAssertSwiftTest(
    _ path: AbsolutePath,
    configuration: BuildConfiguration = .debug,
    extraArgs: [String] = [],
    Xcc: [String] = [],
    Xld: [String] = [],
    Xswiftc: [String] = [],
    env: Environment? = nil,
    file: StaticString = #file,
    line: UInt = #line,
    buildSystem: BuildSystemProvider.Kind,
) async {
    await XCTAssertAsyncNoThrow(
        try await executeSwiftTest(
            path,
            configuration: configuration,
            extraArgs: extraArgs,
            Xcc: Xcc,
            Xld: Xld,
            Xswiftc: Xswiftc,
            env: env,
            buildSystem: buildSystem
        ),
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
    env: Environment? = nil,
    file: StaticString = #file,
    line: UInt = #line,
    buildSystem: BuildSystemProvider.Kind,
) async -> CommandExecutionError? {
    var failure: CommandExecutionError? = nil
    await XCTAssertThrowsCommandExecutionError(
        try await executeSwiftBuild(
            path,
            Xcc: Xcc,
            Xld: Xld,
            Xswiftc: Xswiftc,
            buildSystem: buildSystem
        ),
        file: file,
        line: line
    ) { error in
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

public func XCTAssertAsyncTrue(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let result = try await expression()
    XCTAssertTrue(result, message(), file: file, line: line)
}

public func XCTAssertAsyncFalse(
    _ expression: @autoclosure () async throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let result = try await expression()
    XCTAssertFalse(result, message(), file: file, line: line)
}

package func XCTAssertAsyncNil(
    _ expression: @autoclosure () async throws -> Any?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async rethrows {
    let result = try await expression()
    XCTAssertNil(result, message(), file: file, line: line)
}

public func XCTAssertThrowsCommandExecutionError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: CommandExecutionError) -> Void = { _ in }
) async {
    await XCTAssertAsyncThrowsError(try await expression(), message(), file: file, line: line) { error in
        guard case SwiftPMError.executionFailure(let processError, let stdout, let stderr) = error,
              case AsyncProcessResult.Error.nonZeroExit(let processResult) = processError,
              processResult.exitStatus != .terminated(code: 0) else {
            return XCTFail("Unexpected error type: \(error.interpolationDescription)", file: file, line: line)
        }
        errorHandler(CommandExecutionError(result: processResult, stdout: stdout, stderr: stderr))
    }
}

public func XCTAssertAsyncEqual<T: Equatable>(
    _ expression1: @autoclosure () async throws -> T,
    _ expression2: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) async rethrows {
    let value1 = try await expression1()
    let value2 = try await expression2()

    XCTAssertEqual(value1, value2, message(), file: file, line: line)
}

struct XCAsyncTestErrorWhileUnwrappingOptional: Error {}

public func XCTAsyncUnwrap<T>(
    _ expression: @autoclosure () async throws -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    guard let result = try await expression() else {
        throw XCAsyncTestErrorWhileUnwrappingOptional()
    }

    return result
}


public struct CommandExecutionError: Error {
    package let result: AsyncProcessResult
    public let stdout: String
    public let stderr: String

    package init(result: AsyncProcessResult, stdout: String, stderr: String) {
        self.result = result
        self.stdout = stdout
        self.stderr = stderr
    }
}


public func XCTExhibitsGitHubIssue(_ number: Int) throws {
    let envVar = "SWIFTCI_EXHIBITS_GH_\(number)"

    try XCTSkipIf(
        ProcessInfo.processInfo.environment[envVar] != nil,
        "https://github.com/swiftlang/swift-package-manager/issues/\(number): \(envVar) environment variable is set"
    )
}
