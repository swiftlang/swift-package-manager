/*
 This source file is part of the Swift.org open source project
 
 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import class Foundation.ProcessInfo

import enum POSIX.SystemError
import libc
import Basic

/// Process result data which is available after process termination.
public struct ProcessResult {

    public enum Error: Swift.Error {
        /// The output is not a valid UTF8 sequence.
        case illegalUTF8Sequence
    }

    public enum ExitStatus {
        /// The process was terminated normally with a exit code.
        case terminated(code: Int32)

        /// The process was terminated due to a signal.
        case signalled(signal: Int32)
    }

    /// The exit status of the process.
    public let exitStatus: ExitStatus

    /// The output bytes of the process. Available only if the process was asked to redirect its output.
    public let output: Result<[Int8], AnyError>

    /// Create an instance using the process exit code and output result.
    fileprivate init(exitStatus: Int32, output: Result<[Int8], AnyError>) {
        self.output = output
        if WIFSIGNALED(exitStatus) {
            self.exitStatus = .signalled(signal: WTERMSIG(exitStatus))
        } else {
            precondition(WIFEXITED(exitStatus), "unexpected exit status \(exitStatus)")
            self.exitStatus = .terminated(code: WEXITSTATUS(exitStatus))
        }
    }

    /// Converts output bytes to string, assuming they're UTF8.
    ///
    /// - Throws: Error while reading the process output or if output is not a valid UTF8 sequence.
    public func utf8Output() throws -> String {
        var bytes = try output.dematerialize()
        // Null terminate it.
        bytes.append(0)
        if let output = String(validatingUTF8: bytes) {
            return output
        }
        throw Error.illegalUTF8Sequence
    }
}

/// Process allows spawning new subprocesses and working with them.
///
/// Note: This class is not thread safe.
public final class Process: ObjectIdentifierProtocol {

    /// Typealias for process id type.
    public typealias ProcessID = pid_t

    /// The arguments to execute.
    public let arguments: [String]

    /// The environment with which the process was executed.
    public let environment: [String: String]

    /// The process id of the spawned process, available after the process is launched.
    public private(set) var processID = ProcessID()

    /// The result of the process execution. Available after process is terminated.
    public private(set) var result: ProcessResult?

    /// If the subprocess has launched.
    public private(set) var launched = false

    /// If process was asked to redirect its output.
    public let redirectOutput: Bool

    /// The thread to read the output from the process, if redirected.
    private var readOutputThread: Thread? = nil

    /// Error encountered during reading of redirected output.
    private var readOutputError: Swift.Error? = nil

    /// The output read from the process, if redirected.
    private var output: [Int8] = []

    /// Create a new process instance.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - redirectOutput: Redirect and store stdout/stderr output (of subprocess) in the process result, instead of printing on
    ///     the standard streams. Default value is true.
    public init(arguments: [String], environment: [String: String] = env(), redirectOutput: Bool = true) {
        self.arguments = arguments
        self.environment = environment
        self.redirectOutput = redirectOutput 
    }

    /// Launch the subprocess.
    public func launch() throws {
        assert(!launched, "It is not allowed to launch the same process object again.")
        launched = true

        // Initialize the spawn attributes.
      #if os(macOS)
        var attributes: posix_spawnattr_t? = nil
      #else
        var attributes = posix_spawnattr_t()
      #endif
        posix_spawnattr_init(&attributes)

        // Unmask all signals.
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        // Reset all signals to default behavior.
      #if os(macOS)
        var mostSignals = sigset_t()
        sigfillset(&mostSignals)
        sigdelset(&mostSignals, SIGKILL)
        sigdelset(&mostSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &mostSignals)
      #else
        // On Linux, this can only be used to reset signals that are legal to
        // modify, so we have to take care about the set we use.
        var mostSignals = sigset_t()
        sigemptyset(&mostSignals);
        for i in 1 ..< SIGUNUSED {
            if i == SIGKILL || i == SIGSTOP {
                continue
            }
            sigaddset(&mostSignals, i)
        }
        posix_spawnattr_setsigdefault(&attributes, &mostSignals)
      #endif

        // Establish a separate process group.
        posix_spawnattr_setpgroup(&attributes, 0)

        // Set the attribute flags.
        var flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        flags |= POSIX_SPAWN_SETPGROUP

        // Close all other files by default.
        //
        // FIXME: Note that this is an Apple-specific extension, and we will have to
        // do something else on other platforms (and unfortunately, there isn't
        // really an easy answer other than using a stub executable).
      #if os(macOS)
        flags |= POSIX_SPAWN_CLOEXEC_DEFAULT
      #endif

        posix_spawnattr_setflags(&attributes, Int16(flags))

        // Setup the file actions.
      #if os(macOS)
        var fileActions: posix_spawn_file_actions_t? = nil
      #else
        var fileActions = posix_spawn_file_actions_t()
      #endif
        posix_spawn_file_actions_init(&fileActions)

        // Workaround for https://sourceware.org/git/gitweb.cgi?p=glibc.git;h=89e435f3559c53084498e9baad22172b64429362
        let devNull = strdup("/dev/null")
        defer { free(devNull) }
        // Open /dev/null as stdin.
        posix_spawn_file_actions_addopen(&fileActions, 0, devNull, O_RDONLY, 0)

        var outputPipe: [Int32] = [0, 0]
        if redirectOutput {
            let rv = libc.pipe(&outputPipe)
            guard rv == 0 else {
                throw SystemError.pipe(rv)
            }
            // Open the write end of the pipe as stdout and stderr, if desired.
            posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], 1)
            posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], 2)

            // Close the other ends of the pipe.
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[1])
        } else {
            posix_spawn_file_actions_adddup2(&fileActions, 1, 1)
            posix_spawn_file_actions_adddup2(&fileActions, 2, 2)
        }

        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map{ $0.withCString(strdup) }
        argv.append(nil)
        defer { for case let arg? in argv { free(arg) } }
        
        var env: [UnsafeMutablePointer<CChar>?] = environment.map{ "\($0.0)=\($0.1)".withCString(strdup) }
        env.append(nil)
        defer { for case let arg? in env { free(arg) } }

        let rv = posix_spawnp(&processID, argv[0], &fileActions, &attributes, argv, env)
        guard rv == 0 else {
            throw SystemError.posix_spawn(rv, arguments)
        }

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attributes)

        if redirectOutput {
            // Close the write end of the output pipe.
            let rv = close(outputPipe[1])
            guard rv == 0 else {
                throw SystemError.close(rv)
            }
            // Create a thread and start reading the output on it.
            let thread = Thread {
                self.readOutput(onFD: outputPipe[0])
            }
            thread.start()
            readOutputThread = thread
        }
    }

    /// Blocks the calling process until the subprocess finishes execution.
    @discardableResult
    public func waitUntilExit() throws -> ProcessResult {
        precondition(launched, "The process is not yet launched.")
        // If we're reading output, make sure that is finished.
        if let thread = readOutputThread {
            assert(redirectOutput)
            thread.join()
        }
        // Wait until process finishes execution.
        var exitStatus: Int32 = 0
        var result = waitpid(processID, &exitStatus, 0)
        while (result == -1 && errno == EINTR) {
            result = waitpid(processID, &exitStatus, 0)
        }
        if result == -1 {
            throw SystemError.waitpid(errno)
        }

        // Construct the result.
        let outputResult = readOutputError.map(Result.init) ?? Result(output)
        let executionResult = ProcessResult(exitStatus: exitStatus, output: outputResult)
        self.result = executionResult
        return executionResult
    }

    /// Reads the output from the passed fd and writes in the output variable
    /// after reading all of the data.
    private func readOutput(onFD fd: Int32) {
        // Read all of the data from the output pipe.
        let N = 4096
        var buf = [Int8](repeating: 0, count: N + 1)
        
        var out = [Int8]()
        var error: Swift.Error? = nil
        loop: while true {
            let n = read(fd, &buf, N)
            switch n {
            case  -1:
                if errno == EINTR {
                    continue
                } else {
                    error = SystemError.read(errno)
                    break loop
                }
            case 0:
                break loop
            default:
                out += buf[0..<n]
            }
        }

        output = out
        readOutputError = error
        // Close the read end of the output pipe.
        close(fd)
    }

    /// Send a signal to the process.
    ///
    /// Note: This will signal all processes in the process group.
    public func signal(_ signal: Int32) {
        assert(launched, "The process is not yet launched.")
        assert(result == nil, "The process has already terminated. \(result.debugDescription)")
        _ = libc.kill(-processID, signal)
    }
}

extension Process {
    /// Execute a subprocess and block until it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    /// - Returns: The process result.
    static public func popen(arguments: [String], environment: [String: String] = env()) throws -> ProcessResult {
        let process = Process(arguments: arguments, environment: environment, redirectOutput: true)
        try process.launch()
        return try process.waitUntilExit()
    }

    static public func popen(args: String..., environment: [String: String] = env()) throws -> ProcessResult {
        return try Process.popen(arguments: args, environment: environment)
    }

    public convenience init(args: String..., environment: [String: String] = env(), redirectOutput: Bool = true) {
        self.init(arguments: args, environment: environment, redirectOutput: redirectOutput)
    }
}

// MARK:- Private helpers

#if os(macOS)
private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t?
#else
private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t
#endif

/// The current environment.
private func env() -> [String: String] {
    return ProcessInfo.processInfo.environment
}

private func WIFEXITED(_ status: Int32) -> Bool {
    return _WSTATUS(status) == 0
}

private func _WSTATUS(_ status: Int32) -> Int32 {
    return status & 0x7f
}

private func WIFSIGNALED(_ status: Int32) -> Bool {
    return (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7f)
}

private func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xff
}

private func WTERMSIG(_ status: Int32) -> Int32 {
    return status & 0x7f
}

extension ProcessResult.ExitStatus: Equatable {
    public static func ==(lhs: ProcessResult.ExitStatus, rhs: ProcessResult.ExitStatus) -> Bool {
        switch (lhs, rhs) {
        case (.terminated(let l), .terminated(let r)):
            return l == r
        case (.terminated(_), _):
            return false
        case (.signalled(let l), .signalled(let r)):
            return l == r
        case (.signalled(_), _):
            return false
        }
    }
}
