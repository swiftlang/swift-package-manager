/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func POSIX.getenv
import enum POSIX.Error
import Foundation

public func popen(_ arguments: [String], redirectStandardError: Bool = false, environment: [String: String] = [:]) throws -> String
{
    var out = ""
    try popen(arguments, redirectStandardError: redirectStandardError, environment: environment) {
        out += $0
    }
    return out
}

public func popen(_ arguments: [String], redirectStandardError: Bool = false, environment customEnvironment: [String: String] = [:], body: (String) -> Void) throws
{
    let task = NSTask()

    var arguments = arguments
    task.launchPath = try which(arguments.removeFirst())
    task.arguments = arguments

    var environment = defaultEnvironment
    for (key, value) in customEnvironment {
        environment[key] = value
    }
    task.environment = environment

    let pipe = NSPipe()
    task.standardOutput = pipe

    if redirectStandardError {
        task.standardError = pipe
    }

    task.launch()

    repeat {
        guard let output = String(data: pipe.fileHandleForReading.availableData, encoding: NSUTF8StringEncoding) else {
            throw Error.UnicodeDecodingError
        }
        body(output)
    } while task.isRunning

    guard task.terminationStatus == 0 else {
        throw POSIX.Error.ExitStatus(task.terminationStatus, task.launchPath!, arguments)
    }
}
