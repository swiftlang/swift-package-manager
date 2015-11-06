/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import libc

public func popen(arguments: [String], redirectStandardError: Bool = false, environment: [String: String] = [:]) throws -> String
{
    do {
        // Create a pipe to use for reading the result.
        var pipe: [Int32] = [0, 0]
        var rv = libc.pipe(&pipe)
        guard rv == 0 else {
            throw SystemError.pipe(rv)
        }

        // Create the file actions to use for spawning.
        var fileActions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fileActions)

        // Open /dev/null as stdin.
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0);

        // Open the write end of the pipe as stdout (and stderr, if desired).
        posix_spawn_file_actions_adddup2(&fileActions, pipe[1], 1);
        if redirectStandardError {
            posix_spawn_file_actions_adddup2(&fileActions, pipe[1], 2);
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
        var buf = [Int8](count: N + 1, repeatedValue: 0)
        var out = [Int8]()

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
                out.appendContentsOf(buf[0..<n])
            }
        }

        // Close the read end of the output pipe.
        close(pipe[0])

        // Convert the buffer to a string.
        out += [0]
        let result = String.fromCString(out)!  //FIXME no bang, error gracefully instead

        // Wait for the command to exit.
        let exitStatus = try POSIX.waitpid(pid)

        guard exitStatus == 0 else {
            throw Error.ExitStatus(exitStatus, arguments)
        }

        return result

    } catch let underlyingError as SystemError {
        throw ShellError.popen(arguments: arguments, underlyingError)
    }
}
