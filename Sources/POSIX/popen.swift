/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

public func popen(_ arguments: [String], redirectStandardError: Bool = false, environment: [String: String] = [:]) throws -> String
{
    var out = ""
    try popen(arguments, redirectStandardError: redirectStandardError, environment: environment) { line in
        out += line
    }
    return out
}

public func popen(_ arguments: [String], redirectStandardError: Bool = false, environment: [String: String] = [:], body: (String) -> Void) throws
{
    do {
        // Create a pipe to use for reading the result.
        var pipe: [Int32] = [0, 0]
        var rv = libc.pipe(&pipe)
        guard rv == 0 else {
            throw SystemError.pipe(rv)
        }

        // Create the file actions to use for spawning.
#if os(OSX)
        var fileActions: posix_spawn_file_actions_t? = nil
#else
        var fileActions = posix_spawn_file_actions_t()
#endif
        posix_spawn_file_actions_init(&fileActions)

        // Open /dev/null as stdin.
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)

        // Open the write end of the pipe as stdout (and stderr, if desired).
        posix_spawn_file_actions_adddup2(&fileActions, pipe[1], 1)
        if redirectStandardError {
            posix_spawn_file_actions_adddup2(&fileActions, pipe[1], 2)
        }

        // Close the other ends of the pipe.
        posix_spawn_file_actions_addclose(&fileActions, pipe[0])
        posix_spawn_file_actions_addclose(&fileActions, pipe[1])

        // Launch the command.
        let pid = try POSIX.posix_spawnp(arguments[0], args: arguments, environment: environment, fileActions: fileActions)

        // Clean up the file actions.
        posix_spawn_file_actions_destroy(&fileActions)

        // Close the write end of the output pipe.
        rv = close(pipe[1])
        guard rv == 0 else {
            throw SystemError.close(rv)
        }

        // Read all of the data from the output pipe.
        let N = 4096
        var buf = [Int8](repeating: 0, count: N + 1)

        loop: while true {
            let n = read(pipe[0], &buf, N)
            switch n {
            case  -1:
                if errno == EINTR {
                    continue  // try again!
                } else {
                    throw SystemError.read(errno)
                }
            case 0:
                break loop
            default:
                buf[n] = 0 // must null terminate
                if let str = String(validatingUTF8: buf) {
                    body(str)
                } else {
                    throw SystemError.popen(EILSEQ, arguments[0])
                }
            }
        }

        // Close the read end of the output pipe.
        close(pipe[0])

        // Wait for the command to exit.
        let exitStatus = try POSIX.waitpid(pid)

        guard exitStatus == 0 else {
            throw Error.ExitStatus(exitStatus, arguments)
        }

    } catch let underlyingError as SystemError {
        throw ShellError.popen(arguments: arguments, underlyingError)
    }
}
