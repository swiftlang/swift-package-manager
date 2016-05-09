/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
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
public func system(_ args: String...) throws {
    try system(args)
}

/**
 Execute the specified arguments where the first argument is
 the tool. Uses PATH to find the tool if the first argument
 path is not absolute.
*/
public func system(_ arguments: [String], environment: [String:String] = [:]) throws {
    // make sure subprocess output doesn't get interleaved with our own
    fflush(stdout)

    do {
        let pid = try posix_spawnp(arguments[0], args: arguments, environment: environment)
        let exitStatus = try waitpid(pid)
        guard exitStatus == 0 else { throw Error.ExitStatus(exitStatus, arguments) }
    } catch let underlyingError as SystemError {
        throw ShellError.system(arguments: arguments, underlyingError)
    }
}

@available(*, unavailable)
public func system() {}


#if os(OSX)
typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t?
#else
typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t
#endif

/// Convenience wrapper for posix_spawn.
func posix_spawnp(_ path: String, args: [String], environment: [String: String] = [:], fileActions: swiftpm_posix_spawn_file_actions_t? = nil) throws -> pid_t {
    let argv: [UnsafeMutablePointer<CChar>?] = args.map{ $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }

    var environment = environment
#if Xcode
    let keys = ["SWIFT_EXEC", "HOME", "PATH", "TOOLCHAINS", "DEVELOPER_DIR"]
#else
    let keys = ["SWIFT_EXEC", "HOME", "PATH", "SDKROOT", "TOOLCHAINS", "DEVELOPER_DIR"]
#endif
    for key in keys {
        if environment[key] == nil {
            environment[key] = POSIX.getenv(key)
        }
    }

    let env: [UnsafeMutablePointer<CChar>?] = environment.map{ "\($0.0)=\($0.1)".withCString(strdup) }
    defer { for case let arg? in env { free(arg) } }
    
    var pid = pid_t()
    let rv: Int32
    if var fileActions = fileActions {
        rv = posix_spawnp(&pid, argv[0], &fileActions, nil, argv + [nil], env + [nil])
    } else {
        rv = posix_spawnp(&pid, argv[0], nil, nil, argv + [nil], env + [nil])
    }
    guard rv == 0 else {
        throw SystemError.posix_spawn(rv, args)
    }

    return pid
}


private func _WSTATUS(_ status: CInt) -> CInt {
    return status & 0x7f
}

private func WIFEXITED(_ status: CInt) -> Bool {
    return _WSTATUS(status) == 0
}

private func WEXITSTATUS(_ status: CInt) -> CInt {
    return (status >> 8) & 0xff
}


/// convenience wrapper for waitpid
func waitpid(_ pid: pid_t) throws -> Int32 {
    while true {
        var exitStatus: Int32 = 0
        let rv = waitpid(pid, &exitStatus, 0)

        if rv != -1 {
            if WIFEXITED(exitStatus) {
                return WEXITSTATUS(exitStatus)
            } else {
                throw Error.ExitSignal
            }
        } else if errno == EINTR {
            continue  // see: man waitpid
        } else {
            throw SystemError.waitpid(errno)
        }
    }
}
