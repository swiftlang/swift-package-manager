//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import struct TSCBasic.ProcessEnvironmentBlock

import struct TSCBasic.AbsolutePath
import class TSCBasic.Process
import struct TSCBasic.ProcessResult

import Dispatch

// FIXME: remove ProcessEnvironmentBlockShims
// only needed outside this module for Git
extension Environment {
    @_spi(ProcessEnvironmentBlockShim)
    public init(_ processEnvironmentBlock: ProcessEnvironmentBlock) {
        self.init()
        for (key, value) in processEnvironmentBlock {
            self[.init(key.value)] = value
        }
    }
}

extension ProcessEnvironmentBlock {
    @_spi(ProcessEnvironmentBlockShim)
    public init(_ environment: Environment) {
        self.init()
        for (key, value) in environment {
            self[.init(key.rawValue)] = value
        }
    }
}

// MARK: - Process Shims

extension TSCBasic.Process {
    package convenience init(
        arguments: [String],
        environment: Environment = .current,
        workingDirectory: TSCBasic.AbsolutePath? = nil,
        outputRedirection: OutputRedirection = .collect,
        startNewProcessGroup: Bool = true,
        loggingHandler: LoggingHandler? = .none
    ) {
        if let workingDirectory {
            self.init(
                arguments: arguments,
                environmentBlock: .init(environment),
                workingDirectory: workingDirectory,
                outputRedirection: outputRedirection,
                startNewProcessGroup: startNewProcessGroup,
                loggingHandler: loggingHandler
            )
        } else {
            self.init(
                arguments: arguments,
                environmentBlock: .init(environment),
                outputRedirection: outputRedirection,
                startNewProcessGroup: startNewProcessGroup,
                loggingHandler: loggingHandler
            )
        }
    }
}

extension TSCBasic.Process {
    package static func popen(
        arguments: [String],
        environment: Environment,
        loggingHandler: LoggingHandler? = nil,
        queue: DispatchQueue? = nil,
        completion: @escaping (Result<ProcessResult, Swift.Error>) -> Void
    ) {
        popen(
            arguments: arguments,
            environmentBlock: .init(environment),
            loggingHandler: loggingHandler,
            queue: queue,
            completion: completion
        )
    }

    @discardableResult
    package static func popen(
        arguments: [String],
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) throws -> ProcessResult {
        try popen(arguments: arguments, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }

    @discardableResult
    package static func popen(
        args: String...,
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) throws -> ProcessResult {
        try popen(arguments: args, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }

    package static func popen(
        arguments: [String],
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) async throws -> ProcessResult {
        try await popen(arguments: arguments, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }

    package static func popen(
        args: String...,
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) async throws -> ProcessResult {
        try await popen(arguments: args, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }
}

extension TSCBasic.Process {
    @discardableResult
    package static func checkNonZeroExit(
        arguments: [String],
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) throws -> String {
        try checkNonZeroExit(arguments: arguments, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }

    @discardableResult
    package static func checkNonZeroExit(
        arguments: [String],
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) async throws -> String {
        try await checkNonZeroExit(
            arguments: arguments,
            environmentBlock: .init(environment),
            loggingHandler: loggingHandler
        )
    }

    @discardableResult
    package static func checkNonZeroExit(
        args: String...,
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) throws -> String {
        try checkNonZeroExit(arguments: args, environmentBlock: .init(environment), loggingHandler: loggingHandler)
    }

    @discardableResult
    package static func checkNonZeroExit(
        args: String...,
        environment: Environment,
        loggingHandler: LoggingHandler? = nil
    ) async throws -> String {
        try await checkNonZeroExit(
            arguments: args,
            environmentBlock: .init(environment),
            loggingHandler: loggingHandler
        )
    }
}

// MARK: ProcessResult Shims

extension ProcessResult {
    package init(
        arguments: [String],
        environment: Environment,
        exitStatus: ExitStatus,
        output: Result<[UInt8], Swift.Error>,
        stderrOutput: Result<[UInt8], Swift.Error>
    ) {
        self.init(
            arguments: arguments,
            environmentBlock: .init(environment),
            exitStatus: exitStatus,
            output: output,
            stderrOutput: stderrOutput
        )
    }
}
