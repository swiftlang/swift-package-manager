/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import libc

/**
 Execute the specified arguments where the first argument is
 the tool. Uses PATH to find the tool if the first argument
 path is not absolute.
*/
public func system(args: String...) throws {
    try system(args)
}

/**
 Execute the specified arguments where the first argument is
 the tool. Uses PATH to find the tool if the first argument
 path is not absolute.
*/
public func system(arguments: [String]) throws {
    do {
        let pid = try posix_spawnp(arguments[0], args: arguments)
        let exitStatus = try waitpid(pid)
        guard exitStatus == 0 else { throw Error.ExitStatus(exitStatus, arguments) }
    } catch let underlyingError as SystemError {
        throw ShellError.system(arguments: arguments, underlyingError)
    }
}

@available(*, unavailable)
public func system() {}



/// Convenience wrapper for posix_spawn.
func posix_spawnp(path: String, args: [String], var environment: [String: String] = [:], fileActions: posix_spawn_file_actions_t? = nil) throws -> pid_t {
    let argv = args.map{ $0.withCString(strdup) }
    defer { for arg in argv { free(arg) } }

    for key in ["PATH", "SDKROOT", "HOME"] {
        if let value = POSIX.getenv(key) {
            environment[key] = value
        }
    }

    let env = environment.map{ "\($0.0)=\($0.1)".withCString(strdup) }
    defer { env.forEach{ free($0) } }
    
    var pid = pid_t()
    let rv: Int32
    if fileActions != nil {
        var fileActions = fileActions!
        rv = posix_spawnp(&pid, argv[0], &fileActions, nil, argv + [nil], env + [nil])
    } else {
        rv = posix_spawnp(&pid, argv[0], nil, nil, argv + [nil], env + [nil])
    }
    guard rv == 0 else {
        throw SystemError.posix_spawn(rv, args)
    }

    return pid
}

/// convenience wrapper for waitpid
func waitpid(pid: pid_t) throws -> Int32 {
    while true {
        var exitStatus: Int32 = 0
        let rv = waitpid(pid, &exitStatus, 0)

        if rv != -1 {
            return exitStatus
        } else if errno == EINTR {
            continue  // see docs
        } else {
            throw SystemError.waitpid(errno)
        }
    }
}
