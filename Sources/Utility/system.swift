/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import enum POSIX.Error
import func POSIX.getenv
import Foundation

/**
 Execute the specified arguments where the first argument is
 the tool. Uses PATH to find the tool if the first argument
 path is not absolute.
 */
public func system(_ args: String...) throws {
    try system(args)
}

/**
 Execute the specified arguments where the first argument is
 the tool. Uses PATH to find the tool if the first argument
 path is not absolute.
 */
public func system(_ arguments: [String], environment customEnvironment: [String:String] = [:]) throws {
    printArgumentsIfVerbose(arguments)

    let task = NSTask()

    var arguments = arguments
    task.launchPath = which(arguments.removeFirst())
    task.arguments = arguments

    var environment = defaultEnvironment
    for (key, value) in customEnvironment {
        environment[key] = value
    }
    task.environment = environment

    task.launch()
    task.waitUntilExit()

    guard task.terminationStatus == 0 else {
        throw POSIX.Error.ExitStatus(task.terminationStatus, task.launchPath!, arguments)
    }
}


import func libc.fflush

public func system(_ arguments: String..., environment: [String:String] = [:], message: String?) throws {
    var out = ""
    do {
        if Utility.verbosity == .Concise {
            if let message = message {
                print(message)
                fflush(stdout)  // ensure we display `message` before git asks for credentials
            }
            try Utility.popen(arguments, redirectStandardError: true, environment: environment) { line in
                out += line
            }
        } else {
            try system(arguments, environment: environment)
        }
    } catch {
        if verbosity == .Concise {
            print(prettyArguments(arguments), to: &stderr)
            print(out, to: &stderr)
        }
        throw error
    }
}

