/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Basic

extension Process {
    @discardableResult
    static public func checkNonZeroExit(arguments: [String], environment: [String: String] = env, diagnostics: DiagnosticsEngine) throws -> String {
        let process = Process(arguments: arguments, environment: environment, redirectOutput: true)
        try process.launch()
        let result = try process.waitUntilExit()
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            diagnostics.emit(data: ProcessExecutionError(result))
            throw Diagnostics.fatalError
        }
        return try result.utf8Output()
    }
}
