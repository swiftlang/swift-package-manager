/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Dispatch
import Foundation
import _Concurrency

import class TSCBasic.CStringArray
import class TSCBasic.LocalFileOutputByteStream
import enum TSCBasic.SystemError
import class TSCBasic.Thread
import protocol TSCBasic.WritableByteStream

/// Process result data which is available after process termination.

/// Process allows spawning new subprocesses and working with them.
///
/// Note: This class is thread safe.

// MARK: - Private helpers

#if os(Windows)
    import TSCLibc
    import WinSDK
#elseif canImport(Android)
    import Android
#endif  // #if os(Linux)
#if os(Linux)
    #if USE_IMPL_ONLY_IMPORTS
        @_implementationOnly import func TSCclibc.SPM_posix_spawn_file_actions_addchdir_np_supported

        @_implementationOnly import func TSCclibc.SPM_posix_spawn_file_actions_addchdir_np
    #else
        private import func TSCclibc.SPM_posix_spawn_file_actions_addchdir_np_supported
        private import func TSCclibc.SPM_posix_spawn_file_actions_addchdir_np
    #endif  // #if USE_IMPL_ONLY_IMPORTS
#endif  // #if os(Linux)
package struct AsyncProcessResult: CustomStringConvertible, Sendable {
    package enum Error: Swift.Error, Sendable {
        /// The output is not a valid UTF8 sequence.
        case illegalUTF8Sequence

        /// The process had a non zero exit.
        case nonZeroExit(AsyncProcessResult)

        /// The process failed with a `SystemError` (this is used to still provide context on the process that was
        /// launched).
        case systemError(arguments: [String], underlyingError: Swift.Error)
    }

    package enum ExitStatus: Equatable, Sendable {
        /// The process was terminated normally with a exit code.
        case terminated(code: Int32)
        #if os(Windows)
            /// The process was terminated abnormally.
            case abnormal(exception: UInt32)
        #else
            /// The process was terminated due to a signal.
            case signalled(signal: Int32)
        #endif
    }

    /// The arguments with which the process was launched.
    package let arguments: [String]

    /// The environment with which the process was launched.
    package let environment: Environment

    /// The exit status of the process.
    package let exitStatus: ExitStatus

    /// The output bytes of the process. Available only if the process was
    /// asked to redirect its output and no stdout output closure was set.
    package let output: Result<[UInt8], Swift.Error>

    /// The output bytes of the process. Available only if the process was
    /// asked to redirect its output and no stderr output closure was set.
    package let stderrOutput: Result<[UInt8], Swift.Error>

    /// Create an instance using a POSIX process exit status code and output result.
    ///
    /// See `waitpid(2)` for information on the exit status code.
    package init(
        arguments: [String],
        environment: Environment,
        exitStatusCode: Int32,
        normal: Bool,
        output: Result<[UInt8], Swift.Error>,
        stderrOutput: Result<[UInt8], Swift.Error>
    ) {
        let exitStatus: ExitStatus
        #if os(Windows)
            if normal {
                exitStatus = .terminated(code: exitStatusCode)
            } else {
                exitStatus = .abnormal(exception: UInt32(exitStatusCode))
            }
        #else
            if WIFSIGNALED(exitStatusCode) {
                exitStatus = .signalled(signal: WTERMSIG(exitStatusCode))
            } else {
                precondition(WIFEXITED(exitStatusCode), "unexpected exit status \(exitStatusCode)")
                exitStatus = .terminated(code: WEXITSTATUS(exitStatusCode))
            }
        #endif
        self.init(
            arguments: arguments,
            environment: environment,
            exitStatus: exitStatus,
            output: output,
            stderrOutput: stderrOutput
        )
    }

    /// Create an instance using an exit status and output result.
    package init(
        arguments: [String],
        environment: Environment,
        exitStatus: ExitStatus,
        output: Result<[UInt8], Swift.Error>,
        stderrOutput: Result<[UInt8], Swift.Error>
    ) {
        self.arguments = arguments
        self.environment = environment
        self.output = output
        self.stderrOutput = stderrOutput
        self.exitStatus = exitStatus
    }

    /// Converts stdout output bytes to string, assuming they're UTF8.
    package func utf8Output() throws -> String {
        try String(decoding: output.get(), as: Unicode.UTF8.self)
    }

    /// Converts stderr output bytes to string, assuming they're UTF8.
    package func utf8stderrOutput() throws -> String {
        try String(decoding: stderrOutput.get(), as: Unicode.UTF8.self)
    }

    package var description: String {
        """
        <AsyncProcessResult: exit: \(exitStatus), output:
            \((try? utf8Output()) ?? "")
        >
        """
    }
}  // #if os(Linux)
extension AsyncProcess: @unchecked Sendable {}  // #if os(Linux)
extension DispatchQueue {
    // a shared concurrent queue for running concurrent asynchronous operations
    static let processConcurrent = DispatchQueue(
        label: "swift.org.swift-tsc.process.concurrent",
        attributes: .concurrent
    )
}  // #if os(Linux)
package final class AsyncProcess {
    /// Errors when attempting to invoke a process
    package enum Error: Swift.Error, Sendable {
        /// The program requested to be executed cannot be found on the existing search paths, or is not executable.
        case missingExecutableProgram(program: String)

        /// The current OS does not support the workingDirectory API.
        case workingDirectoryNotSupported

        /// The stdin could not be opened.
        case stdinUnavailable

        #if os(Windows)
            /// Errors from Win32 calls.
            case win32Error(msg: String, code: DWORD)
        #endif
    }

    package typealias ReadableStream = AsyncStream<[UInt8]>

    package enum OutputRedirection: Sendable {
        /// Do not redirect the output
        case none

        /// Collect stdout and stderr output and provide it back via ``AsyncProcessResult`` object. If
        /// `redirectStderr` is `true`, `stderr` be redirected to `stdout`.
        case collect(redirectStderr: Bool)

        /// Stream `stdout` and `stderr` via the corresponding closures. If `redirectStderr` is `true`, `stderr` will
        /// be redirected to `stdout`.
        case stream(stdout: OutputClosure, stderr: OutputClosure, redirectStderr: Bool)

        /// Stream stdout and stderr as `AsyncSequence` provided as an argument to closures passed to
        /// ``AsyncProcess/launch(stdoutStream:stderrStream:)``.
        case asyncStream(
            stdoutStream: ReadableStream,
            stdoutContinuation: ReadableStream.Continuation,
            stderrStream: ReadableStream,
            stderrContinuation: ReadableStream.Continuation
        )

        /// Default collect OutputRedirection that defaults to not redirect stderr. Provided for API compatibility.
        package static let collect: Self = .collect(redirectStderr: false)

        /// Default stream OutputRedirection that defaults to not redirect stderr. Provided for API compatibility.
        package static func stream(stdout: @escaping OutputClosure, stderr: @escaping OutputClosure)
            -> Self
        {
            .stream(stdout: stdout, stderr: stderr, redirectStderr: false)
        }

        package var redirectsOutput: Bool {
            switch self {
            case .none:
                false
            case .collect, .stream, .asyncStream:
                true
            }
        }

        package var outputClosures: (stdoutClosure: OutputClosure, stderrClosure: OutputClosure)? {
            switch self {
            case let .stream(stdoutClosure, stderrClosure, _):
                (stdoutClosure: stdoutClosure, stderrClosure: stderrClosure)

            case let .asyncStream(_, stdoutContinuation, _, stderrContinuation):
                (
                    stdoutClosure: { stdoutContinuation.yield($0) },
                    stderrClosure: { stderrContinuation.yield($0) }
                )

            case .collect, .none:
                nil
            }
        }

        package var redirectStderr: Bool {
            switch self {
            case .collect(let redirectStderr):
                redirectStderr
            case .stream(_, _, let redirectStderr):
                redirectStderr
            default:
                false
            }
        }
    }

    // process execution mutable state
    private enum State {
        case idle
        case readingOutput(sync: DispatchGroup)
        case outputReady(stdout: Result<[UInt8], Swift.Error>, stderr: Result<[UInt8], Swift.Error>)
        case complete(AsyncProcessResult)
        case failed(Swift.Error)
    }

    /// Typealias for process id type.
    #if !os(Windows)
        package typealias ProcessID = pid_t
    #else
        package typealias ProcessID = DWORD
    #endif

    /// Typealias for stdout/stderr output closure.
    package typealias OutputClosure = ([UInt8]) -> Void

    /// Typealias for logging handling closure
    package typealias LoggingHandler = (String) -> Void

    private static var _loggingHandler: LoggingHandler?
    private static let loggingHandlerLock = NSLock()

    /// Global logging handler. Use with care! preferably use instance level instead of setting one globally.
    @available(
        *,
        deprecated,
        message:
            "use instance level `loggingHandler` passed via `init` instead of setting one globally."
    )
    package static var loggingHandler: LoggingHandler? {
        get {
            Self.loggingHandlerLock.withLock {
                self._loggingHandler
            }
        }
        set {
            Self.loggingHandlerLock.withLock {
                self._loggingHandler = newValue
            }
        }
    }

    package let loggingHandler: LoggingHandler?

    /// The arguments to execute.
    package let arguments: [String]

    package let environment: Environment

    /// The path to the directory under which to run the process.
    package let workingDirectory: AbsolutePath?

    /// The process id of the spawned process, available after the process is launched.
    #if os(Windows)
        private var processHandle: HANDLE?
    #else
        package private(set) var processID = ProcessID()
    #endif

    // process execution mutable state
    private var state: State = .idle
    private let stateLock = NSLock()

    private static let sharedCompletionQueue = DispatchQueue(
        label: "org.swift.tools-support-core.process-completion")
    private var completionQueue = AsyncProcess.sharedCompletionQueue

    // ideally we would use the state for this, but we need to access it while the waitForExit is locking state
    private var _launched = false
    private let launchedLock = NSLock()

    package var launched: Bool {
        self.launchedLock.withLock {
            self._launched
        }
    }

    /// How process redirects its output.
    package let outputRedirection: OutputRedirection

    /// Indicates if a new progress group is created for the child process.
    private let startNewProcessGroup: Bool

    /// Cache of validated executables.
    ///
    /// Key: Executable name or path.
    /// Value: Path to the executable, if found.
    private static var validatedExecutablesMap = [String: AbsolutePath?]()
    private static let validatedExecutablesMapLock = NSLock()

    /// Create a new process instance.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - workingDirectory: The path to the directory under which to run the process.
    ///   - outputRedirection: How process redirects its output. Default value is .collect.
    ///   - startNewProcessGroup: If true, a new progress group is created for the child making it
    ///     continue running even if the parent is killed or interrupted. Default value is true.
    ///   - loggingHandler: Handler for logging messages
    ///
    package init(
        arguments: [String],
        environment: Environment = .current,
        workingDirectory: AbsolutePath,
        outputRedirection: OutputRedirection = .collect,
        startNewProcessGroup: Bool = true,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.outputRedirection = outputRedirection
        self.startNewProcessGroup = startNewProcessGroup
        self.loggingHandler = loggingHandler ?? AsyncProcess.loggingHandler
    }

    /// Create a new process instance.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - outputRedirection: How process redirects its output. Default value is .collect.
    ///   - verbose: If true, launch() will print the arguments of the subprocess before launching it.
    ///   - startNewProcessGroup: If true, a new progress group is created for the child making it
    ///     continue running even if the parent is killed or interrupted. Default value is true.
    ///   - loggingHandler: Handler for logging messages
    package init(
        arguments: [String],
        environment: Environment = .current,
        outputRedirection: OutputRedirection = .collect,
        startNewProcessGroup: Bool = true,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = nil
        self.outputRedirection = outputRedirection
        self.startNewProcessGroup = startNewProcessGroup
        self.loggingHandler = loggingHandler ?? AsyncProcess.loggingHandler
    }

    package convenience init(
        args: String...,
        environment: Environment = .current,
        outputRedirection: OutputRedirection = .collect,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.init(
            arguments: args,
            environment: environment,
            outputRedirection: outputRedirection,
            loggingHandler: loggingHandler
        )
    }

    /// Returns the path of the the given program if found in the search paths.
    ///
    /// The program can be executable name, relative path or absolute path.
    package static func findExecutable(
        _ program: String,
        workingDirectory: AbsolutePath? = nil
    ) -> AbsolutePath? {
        if let abs = try? AbsolutePath(validating: program) {
            return abs
        }
        let cwdOpt = workingDirectory ?? localFileSystem.currentWorkingDirectory
        // The program might be a multi-component relative path.
        if let rel = try? RelativePath(validating: program), rel.components.count > 1 {
            if let cwd = cwdOpt {
                let abs = AbsolutePath(cwd, rel)
                if localFileSystem.isExecutableFile(abs) {
                    return abs
                }
            }
            return nil
        }
        // From here on out, the program is an executable name, i.e. it doesn't contain a "/"
        let lookup: () -> AbsolutePath? = {
            let envSearchPaths = getEnvSearchPaths(
                pathString: Environment.current[.path],
                currentWorkingDirectory: cwdOpt
            )
            let value = lookupExecutablePath(
                filename: program,
                currentWorkingDirectory: cwdOpt,
                searchPaths: envSearchPaths
            )
            return value
        }
        // This should cover the most common cases, i.e. when the cache is most helpful.
        if workingDirectory == localFileSystem.currentWorkingDirectory {
            return AsyncProcess.validatedExecutablesMapLock.withLock {
                if let value = AsyncProcess.validatedExecutablesMap[program] {
                    return value
                }
                let value = lookup()
                AsyncProcess.validatedExecutablesMap[program] = value
                return value
            }
        } else {
            return lookup()
        }
    }

    /// Launch the subprocess. Returns a WritableByteStream object that can be used to communicate to the process's
    /// stdin. If needed, the stream can be closed using the close() API. Otherwise, the stream will be closed
    /// automatically.
    @discardableResult
    package func launch() throws -> any WritableByteStream {
        precondition(
            self.arguments.count > 0 && !self.arguments[0].isEmpty,
            "Need at least one argument to launch the process."
        )

        self.launchedLock.withLock {
            precondition(
                !self._launched, "It is not allowed to launch the same process object again.")
            self._launched = true
        }

        // Print the arguments if we are verbose.
        if let loggingHandler = self.loggingHandler {
            loggingHandler(self.arguments.map { $0.spm_shellEscaped() }.joined(separator: " "))
        }

        #if os(Windows)
            var secAttr = SECURITY_ATTRIBUTES()
            secAttr.nLength = DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size)
            secAttr.lpSecurityDescriptor = nil
            secAttr.bInheritHandle = true

            let NULL = OpaquePointer(bitPattern: 0)
            var childStdOutRead = HANDLE(NULL)
            var childStdOutWrite = HANDLE(NULL)

            if !CreatePipe(&childStdOutRead, &childStdOutWrite, &secAttr, 0) {
                throw AsyncProcess.Error.win32Error(
                    msg: "creating stdout pipe", code: GetLastError()
                )
            }

            if !SetHandleInformation(childStdOutRead, HANDLE_FLAG_INHERIT, 0) {
                throw AsyncProcess.Error.win32Error(
                    msg: "setting stdout read inherit", code: GetLastError()
                )
            }

            var childStdErrRead = HANDLE(NULL)
            var childStdErrWrite = HANDLE(NULL)

            if !self.outputRedirection.redirectStderr {
                if !CreatePipe(&childStdErrRead, &childStdErrWrite, &secAttr, 0) {
                    throw AsyncProcess.Error.win32Error(
                        msg: "creating stderr pipe", code: GetLastError()
                    )
                }

                if !SetHandleInformation(childStdErrRead, HANDLE_FLAG_INHERIT, 0) {
                    throw AsyncProcess.Error.win32Error(
                        msg: "setting stderr read inherit", code: GetLastError()
                    )
                }
            } else {
                childStdErrWrite = childStdOutWrite
            }

            var childStdInRead = HANDLE(NULL)
            var childStdinWrite = HANDLE(NULL)

            if !CreatePipe(&childStdInRead, &childStdinWrite, &secAttr, 0) {
                throw AsyncProcess.Error.win32Error(
                    msg: "creating stdin pipe", code: GetLastError()
                )
            }

            if !SetHandleInformation(childStdinWrite, HANDLE_FLAG_INHERIT, 0) {
                throw AsyncProcess.Error.win32Error(
                    msg: "setting stdin write inherit", code: GetLastError()
                )
            }

            var procInfo = PROCESS_INFORMATION()

            var startInfo = STARTUPINFOW()
            startInfo.cb = DWORD(MemoryLayout<STARTUPINFO>.size)
            startInfo.hStdOutput = childStdOutWrite
            startInfo.hStdError = childStdErrWrite
            startInfo.hStdInput = childStdInRead
            startInfo.dwFlags |= STARTF_USESTDHANDLES

            // TODO: need to quote the elements
            let cmdline = quoteWindowsCommandLine(self.arguments)
            let env =
                (self.environment.map({ $0.key.rawValue + "=" + $0.value }).joined(separator: "\0")
                    + "\0\0")
            let flags = DWORD(CREATE_UNICODE_ENVIRONMENT)
            let result = cmdline.withCString(encodedAs: UTF16.self) { cmdlineW in
                env.withCString(encodedAs: UTF16.self) { envW in
                    if let cwd = workingDirectory?.pathString {
                        return cwd.withCString(encodedAs: UTF16.self) { cwdW in
                            return CreateProcessW(
                                nil,
                                UnsafeMutablePointer<WCHAR>(mutating: cmdlineW),
                                nil,
                                nil,
                                true,
                                flags,
                                UnsafeMutablePointer(mutating: envW),
                                cwdW,
                                &startInfo,
                                &procInfo
                            )
                        }
                    } else {
                        return CreateProcessW(
                            nil,
                            UnsafeMutablePointer<WCHAR>(mutating: cmdlineW),
                            nil,
                            nil,
                            true,
                            flags,
                            UnsafeMutablePointer(mutating: envW),
                            nil,
                            &startInfo,
                            &procInfo
                        )
                    }
                }
            }

            if !result {
                let error = GetLastError()
                if error == ERROR_FILE_NOT_FOUND {
                    throw AsyncProcess.Error.missingExecutableProgram(program: self.arguments[0])
                } else {
                    throw AsyncProcess.Error.win32Error(
                        msg: "create process \(self.arguments[0])", code: GetLastError()
                    )
                }
            }

            self.processHandle = procInfo.hProcess

            CloseHandle(procInfo.hThread)
            CloseHandle(childStdOutWrite)
            CloseHandle(childStdErrWrite)
            CloseHandle(childStdInRead)

            var stdout: [UInt8] = []
            let stdoutLock = NSLock()

            var stderr: [UInt8] = []
            let stderrLock = NSLock()

            let group = DispatchGroup()
            if self.outputRedirection.redirectsOutput {
                group.enter()
                let stdoutThread = Thread { [weak self] in
                    let maxSize = 4096
                    while true {
                        let data = [UInt8](unsafeUninitializedCapacity: maxSize) {
                            buffer, initializedCount in
                            var numRead = DWORD(0)
                            if !ReadFile(
                                childStdOutRead, buffer.baseAddress, DWORD(maxSize), &numRead, nil)
                            {
                                initializedCount = 0
                            } else {
                                initializedCount = Int(numRead)
                            }
                        }

                        if data.isEmpty {
                            CloseHandle(childStdOutRead)
                            group.leave()
                            break
                        }

                        self?.outputRedirection.outputClosures?.stdoutClosure(data)
                        stdoutLock.withLock {
                            stdout += data
                        }
                    }
                }

                let stderrThread: Thread?
                if !self.outputRedirection.redirectStderr {
                    group.enter()
                    stderrThread = Thread { [weak self] in
                        let maxSize = 4096
                        while true {
                            let data = [UInt8](unsafeUninitializedCapacity: maxSize) {
                                buffer, initializedCount in
                                var numRead = DWORD(0)
                                if !ReadFile(
                                    childStdErrRead, buffer.baseAddress, DWORD(maxSize), &numRead,
                                    nil)
                                {
                                    initializedCount = 0
                                } else {
                                    initializedCount = Int(numRead)
                                }
                            }

                            if data.isEmpty {
                                CloseHandle(childStdErrRead)
                                group.leave()
                                break
                            }

                            self?.outputRedirection.outputClosures?.stderrClosure(data)
                            stderrLock.withLock {
                                stderr += data
                            }
                        }
                    }
                } else {
                    stderrThread = nil
                }

                stdoutThread.start()
                stderrThread?.start()
            }

            // first set state then start reading threads
            let sync = DispatchGroup()
            sync.enter()
            self.stateLock.withLock {
                self.state = .readingOutput(sync: sync)
            }

            group.notify(queue: self.completionQueue) {
                self.stateLock.withLock {
                    self.state = .outputReady(stdout: .success(stdout), stderr: .success(stderr))
                }
                sync.leave()
            }

            return WritableHandle(childStdinWrite)
        #elseif (!canImport(Darwin) || os(macOS))
            // Look for executable.
            let executable = self.arguments[0]
            guard
                let executablePath = AsyncProcess.findExecutable(
                    executable, workingDirectory: workingDirectory)
            else {
                throw AsyncProcess.Error.missingExecutableProgram(program: executable)
            }

            // Initialize the spawn attributes.
            #if canImport(Darwin) || os(Android) || os(OpenBSD) || os(FreeBSD)
                var attributes: posix_spawnattr_t? = nil
            #else
                var attributes = posix_spawnattr_t()
            #endif
            posix_spawnattr_init(&attributes)
            defer { posix_spawnattr_destroy(&attributes) }

            // Unmask all signals.
            var noSignals = sigset_t()
            sigemptyset(&noSignals)
            posix_spawnattr_setsigmask(&attributes, &noSignals)

            // Reset all signals to default behavior.
            #if canImport(Darwin)
                var mostSignals = sigset_t()
                sigfillset(&mostSignals)
                sigdelset(&mostSignals, SIGKILL)
                sigdelset(&mostSignals, SIGSTOP)
                posix_spawnattr_setsigdefault(&attributes, &mostSignals)
            #else
                // On Linux, this can only be used to reset signals that are legal to
                // modify, so we have to take care about the set we use.
                var mostSignals = sigset_t()
                sigemptyset(&mostSignals)
                for i in 1..<SIGSYS {
                    if i == SIGKILL || i == SIGSTOP {
                        continue
                    }
                    sigaddset(&mostSignals, i)
                }
                posix_spawnattr_setsigdefault(&attributes, &mostSignals)
            #endif

            // Set the attribute flags.
            var flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
            if self.startNewProcessGroup {
                // Establish a separate process group.
                flags |= POSIX_SPAWN_SETPGROUP
                posix_spawnattr_setpgroup(&attributes, 0)
            }

            posix_spawnattr_setflags(&attributes, Int16(flags))

            // Setup the file actions.
            #if canImport(Darwin) || os(Android) || os(OpenBSD) || os(FreeBSD)
                var fileActions: posix_spawn_file_actions_t? = nil
            #else
                var fileActions = posix_spawn_file_actions_t()
            #endif
            posix_spawn_file_actions_init(&fileActions)
            defer { posix_spawn_file_actions_destroy(&fileActions) }

            if let workingDirectory = workingDirectory?.pathString {
                #if canImport(Darwin)
                    // The only way to set a workingDirectory is using an availability-gated initializer, so we don't need
                    // to handle the case where the posix_spawn_file_actions_addchdir_np method is unavailable. This check only
                    // exists here to make the compiler happy.
                    if #available(macOS 10.15, *) {
                        posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
                    }
                #elseif os(FreeBSD)
                    posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
                #elseif os(Linux)
                    guard SPM_posix_spawn_file_actions_addchdir_np_supported() else {
                        throw AsyncProcess.Error.workingDirectoryNotSupported
                    }

                    SPM_posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
                #else
                    throw AsyncProcess.Error.workingDirectoryNotSupported
                #endif
            }

            var stdinPipe: [Int32] = [-1, -1]
            try open(pipe: &stdinPipe)

            guard let fp = fdopen(stdinPipe[1], "wb") else {
                throw AsyncProcess.Error.stdinUnavailable
            }
            let stdinStream = try LocalFileOutputByteStream(filePointer: fp, closeOnDeinit: true)

            // Dupe the read portion of the remote to 0.
            posix_spawn_file_actions_adddup2(&fileActions, stdinPipe[0], 0)

            // Close the other side's pipe since it was dupped to 0.
            posix_spawn_file_actions_addclose(&fileActions, stdinPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, stdinPipe[1])

            var outputPipe: [Int32] = [-1, -1]
            var stderrPipe: [Int32] = [-1, -1]
            if self.outputRedirection.redirectsOutput {
                // Open the pipe.
                try open(pipe: &outputPipe)

                // Open the write end of the pipe.
                posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], 1)

                // Close the other ends of the pipe since they were dupped to 1.
                posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])
                posix_spawn_file_actions_addclose(&fileActions, outputPipe[1])

                if self.outputRedirection.redirectStderr {
                    // If merged was requested, send stderr to stdout.
                    posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
                } else {
                    // If no redirect was requested, open the pipe for stderr.
                    try open(pipe: &stderrPipe)
                    posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], 2)

                    // Close the other ends of the pipe since they were dupped to 2.
                    posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
                    posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])
                }
            } else {
                posix_spawn_file_actions_adddup2(&fileActions, 1, 1)
                posix_spawn_file_actions_adddup2(&fileActions, 2, 2)
            }

            var resolvedArgs = self.arguments
            if workingDirectory != nil {
                resolvedArgs[0] = executablePath.pathString
            }
            let argv = CStringArray(resolvedArgs)
            let env = CStringArray(environment.map { "\($0.0)=\($0.1)" })
            let rv = posix_spawnp(
                &self.processID, argv.cArray[0]!, &fileActions, &attributes, argv.cArray, env.cArray
            )

            guard rv == 0 else {
                throw SystemError.posix_spawn(rv, self.arguments)
            }

            do {
                // Close the local read end of the input pipe.
                try close(fd: stdinPipe[0])

                let group = DispatchGroup()
                if !self.outputRedirection.redirectsOutput {
                    // no stdout or stderr in this case
                    self.stateLock.withLock {
                        self.state = .outputReady(stdout: .success([]), stderr: .success([]))
                    }
                } else {
                    var pending: Result<[UInt8], Swift.Error>?
                    let pendingLock = NSLock()

                    let outputClosures = self.outputRedirection.outputClosures

                    // Close the local write end of the output pipe.
                    try close(fd: outputPipe[1])

                    // Create a thread and start reading the output on it.
                    group.enter()
                    let stdoutThread = Thread { [weak self] in
                        if let readResult = self?.readOutput(
                            onFD: outputPipe[0],
                            outputClosure: outputClosures?.stdoutClosure
                        ) {
                            pendingLock.withLock {
                                if let stderrResult = pending {
                                    self?.stateLock.withLock {
                                        self?.state = .outputReady(
                                            stdout: readResult, stderr: stderrResult)
                                    }
                                } else {
                                    pending = readResult
                                }
                            }
                            group.leave()
                        } else if let stderrResult = (pendingLock.withLock { pending }) {
                            // TODO: this is more of an error
                            self?.stateLock.withLock {
                                self?.state = .outputReady(
                                    stdout: .success([]), stderr: stderrResult)
                            }
                            group.leave()
                        }
                    }

                    // Only schedule a thread for stderr if no redirect was requested.
                    var stderrThread: Thread? = nil
                    if !self.outputRedirection.redirectStderr {
                        // Close the local write end of the stderr pipe.
                        try close(fd: stderrPipe[1])

                        // Create a thread and start reading the stderr output on it.
                        group.enter()
                        stderrThread = Thread { [weak self] in
                            if let readResult = self?.readOutput(
                                onFD: stderrPipe[0],
                                outputClosure: outputClosures?.stderrClosure
                            ) {
                                pendingLock.withLock {
                                    if let stdoutResult = pending {
                                        self?.stateLock.withLock {
                                            self?.state = .outputReady(
                                                stdout: stdoutResult, stderr: readResult)
                                        }
                                    } else {
                                        pending = readResult
                                    }
                                }
                                group.leave()
                            } else if let stdoutResult = (pendingLock.withLock { pending }) {
                                // TODO: this is more of an error
                                self?.stateLock.withLock {
                                    self?.state = .outputReady(
                                        stdout: stdoutResult, stderr: .success([]))
                                }
                                group.leave()
                            }
                        }
                    } else {
                        pendingLock.withLock {
                            pending = .success([])  // no stderr in this case
                        }
                    }

                    // first set state then start reading threads
                    self.stateLock.withLock {
                        self.state = .readingOutput(sync: group)
                    }

                    stdoutThread.start()
                    stderrThread?.start()
                }

                return stdinStream
            } catch {
                throw AsyncProcessResult.Error.systemError(
                    arguments: self.arguments, underlyingError: error)
            }
        #else
            preconditionFailure("Process spawning is not available")
        #endif  // POSIX implementation
    }

    /// Executes the process I/O state machine, returning the result when finished.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    package func waitUntilExit() async throws -> AsyncProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.processConcurrent.async {
                self.waitUntilExit({
                    continuation.resume(with: $0)
                })
            }
        }
    }

    /// Blocks the calling process until the subprocess finishes execution.
    @available(*, noasync)
    @discardableResult
    package func waitUntilExit() throws -> AsyncProcessResult {
        let group = DispatchGroup()
        group.enter()
        var processResult: Result<AsyncProcessResult, Swift.Error>?
        self.waitUntilExit { result in
            processResult = result
            group.leave()
        }
        group.wait()
        return try processResult.unsafelyUnwrapped.get()
    }

    /// Executes the process I/O state machine, calling completion block when finished.
    private func waitUntilExit(
        _ completion: @escaping (Result<AsyncProcessResult, Swift.Error>) -> Void
    ) {
        self.stateLock.lock()
        switch self.state {
        case .idle:
            defer { self.stateLock.unlock() }
            preconditionFailure("The process is not yet launched.")
        case .complete(let result):
            self.stateLock.unlock()
            completion(.success(result))
        case .failed(let error):
            self.stateLock.unlock()
            completion(.failure(error))
        case .readingOutput(let sync):
            self.stateLock.unlock()
            sync.notify(queue: self.completionQueue) {
                self.waitUntilExit(completion)
            }
        case .outputReady(let stdoutResult, let stderrResult):
            defer { self.stateLock.unlock() }
            // Wait until process finishes execution.
            #if os(Windows)
                precondition(self.processHandle != nil, "The process is not yet launched.")
                _ = WaitForSingleObject(self.processHandle, INFINITE)
                var exitCode = DWORD(0)
                _ = GetExitCodeProcess(self.processHandle, &exitCode)
                let exitStatusCode = exitCode & 0x8000_0000 == 0
                    ? Int32(exitCode) : Int32(Int64(0x8000_0000) - Int64(exitCode))
                let normalExit = true
                CloseHandle(self.processHandle)
            #else
                var exitStatusCode: Int32 = 0
                var result = waitpid(processID, &exitStatusCode, 0)
                while result == -1 && errno == EINTR {
                    result = waitpid(self.processID, &exitStatusCode, 0)
                }
                if result == -1 {
                    self.state = .failed(SystemError.waitpid(errno))
                }
                let normalExit = !WIFSIGNALED(result)
            #endif

            // Construct the result.
            let executionResult = AsyncProcessResult(
                arguments: arguments,
                environment: environment,
                exitStatusCode: exitStatusCode,
                normal: normalExit,
                output: stdoutResult,
                stderrOutput: stderrResult
            )
            self.state = .complete(executionResult)
            self.completionQueue.async {
                self.waitUntilExit(completion)
            }
        }
    }

    #if !os(Windows)
        /// Reads the given fd and returns its result.
        ///
        /// Closes the fd before returning.
        private func readOutput(onFD fd: Int32, outputClosure: OutputClosure?) -> Result<
            [UInt8], Swift.Error
        > {
            // Read all of the data from the output pipe.
            let N = 4096
            var buf = [UInt8](repeating: 0, count: N + 1)

            var out = [UInt8]()
            var error: Swift.Error? = nil
            loop: while true {
                let n = read(fd, &buf, N)
                switch n {
                case -1:
                    if errno == EINTR {
                        continue
                    } else {
                        error = SystemError.read(errno)
                        break loop
                    }
                case 0:
                    // Close the read end of the output pipe.
                    // We should avoid closing the read end of the pipe in case
                    // -1 because the child process may still have content to be
                    // flushed into the write end of the pipe. If the read end of the
                    // pipe is closed, then a write will cause a SIGPIPE signal to
                    // be generated for the calling process.  If the calling process is
                    // ignoring this signal, then write fails with the error EPIPE.
                    close(fd)
                    break loop
                default:
                    let data = buf[0..<n]
                    if let outputClosure {
                        outputClosure(Array(data))
                    } else {
                        out += data
                    }
                }
            }
            // Construct the output result.
            return error.map(Result.failure) ?? .success(out)
        }
    #endif

    /// Send a signal to the process.
    ///
    /// Note: This will signal all processes in the process group.
    package func signal(_ signal: Int32) {
        #if os(Windows)
            _ = TerminateProcess(self.processHandle, DWORD(signal))
        #else
            assert(self.launched, "The process is not yet launched.")
            kill(self.startNewProcessGroup ? -self.processID : self.processID, signal)
        #endif
    }
}  // #if os(Linux)
extension AsyncProcess {
    /// Execute a subprocess and returns the result when it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    package static func popen(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> AsyncProcessResult {
        let process = AsyncProcess(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        return try await process.waitUntilExit()
    }

    /// Execute a subprocess and returns the result when it finishes execution
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    package static func popen(
        args: String...,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> AsyncProcessResult {
        try await self.popen(
            arguments: args, environment: environment, loggingHandler: loggingHandler)
    }

    package typealias DuplexStreamHandler =
        @Sendable (_ stdinStream: WritableByteStream, _ stdoutStream: ReadableStream) async throws
        -> Void
    package typealias ReadableStreamHandler =
        @Sendable (_ stderrStream: ReadableStream) async throws -> Void

    /// Launches a new `AsyncProcess` instances, allowing the caller to consume `stdout` and `stderr` output
    /// with handlers that support structured concurrency.
    /// - Parameters:
    ///   - arguments: CLI command used to launch the process.
    ///   - environment: environment variables passed to the launched process.
    ///   - loggingHandler: handler used for logging,
    ///   - stdoutHandler: asynchronous bidirectional handler closure that receives `stdin` and `stdout` streams as
    ///   arguments.
    ///   - stderrHandler: asynchronous unidirectional handler closure that receives `stderr` stream as an argument.
    /// - Returns: ``AsyncProcessResult`` value as received from the underlying ``AsyncProcess/waitUntilExit()`` call
    /// made on ``AsyncProcess`` instance.
    package static func popen(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none,
        stdoutHandler: @escaping DuplexStreamHandler,
        stderrHandler: ReadableStreamHandler? = nil
    ) async throws -> AsyncProcessResult {
        let (stdoutStream, stdoutContinuation) = ReadableStream.makeStream()
        let (stderrStream, stderrContinuation) = ReadableStream.makeStream()

        let process = AsyncProcess(
            arguments: arguments,
            environment: environment,
            outputRedirection: .stream {
                stdoutContinuation.yield($0)
            } stderr: {
                stderrContinuation.yield($0)
            },
            loggingHandler: loggingHandler
        )

        return try await withThrowingTaskGroup(of: Void.self) { group in
            let stdinStream = try process.launch()

            group.addTask {
                try await stdoutHandler(stdinStream, stdoutStream)
            }

            if let stderrHandler {
                group.addTask {
                    try await stderrHandler(stderrStream)
                }
            }

            defer {
                stdoutContinuation.finish()
                stderrContinuation.finish()
            }

            return try await process.waitUntilExit()
        }
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @discardableResult
    package static func checkNonZeroExit(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        let result = try await popen(
            arguments: arguments,
            environment: environment,
            loggingHandler: loggingHandler
        )
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw AsyncProcessResult.Error.nonZeroExit(result)
        }
        return try result.utf8Output()
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @discardableResult
    package static func checkNonZeroExit(
        args: String...,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        try await self.checkNonZeroExit(
            arguments: args,
            environment: environment,
            loggingHandler: loggingHandler
        )
    }
}  // #if os(Linux)
extension AsyncProcess {
    /// Execute a subprocess and calls completion block when it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    ///   - queue: Queue to use for callbacks
    ///   - completion: A completion handler to return the process result
    @available(*, noasync)
    package static func popen(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none,
        queue: DispatchQueue? = nil,
        completion: @escaping (Result<AsyncProcessResult, Swift.Error>) -> Void
    ) {
        let completionQueue = queue ?? Self.sharedCompletionQueue

        do {
            let process = AsyncProcess(
                arguments: arguments,
                environment: environment,
                outputRedirection: .collect,
                loggingHandler: loggingHandler
            )
            process.completionQueue = completionQueue
            try process.launch()
            process.waitUntilExit(completion)
        } catch {
            completionQueue.async {
                completion(.failure(error))
            }
        }
    }

    /// Execute a subprocess and block until it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process result.
    @available(*, noasync)
    @discardableResult
    package static func popen(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> AsyncProcessResult {
        let process = AsyncProcess(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        return try process.waitUntilExit()
    }

    /// Execute a subprocess and block until it finishes execution
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process result.
    @available(*, noasync)
    @discardableResult
    package static func popen(
        args: String...,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> AsyncProcessResult {
        try AsyncProcess.popen(
            arguments: args, environment: environment, loggingHandler: loggingHandler)
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @available(*, noasync)
    @discardableResult
    package static func checkNonZeroExit(
        arguments: [String],
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> String {
        let process = AsyncProcess(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        let result = try process.waitUntilExit()
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw AsyncProcessResult.Error.nonZeroExit(result)
        }
        return try result.utf8Output()
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @available(*, noasync)
    @discardableResult
    package static func checkNonZeroExit(
        args: String...,
        environment: Environment = .current,
        loggingHandler: LoggingHandler? = .none
    ) throws -> String {
        try self.checkNonZeroExit(
            arguments: args, environment: environment, loggingHandler: loggingHandler)
    }
}  // #if os(Linux)
extension AsyncProcess: Hashable {
    package func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    package static func == (lhs: AsyncProcess, rhs: AsyncProcess) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}  // #if os(Linux)
#if !os(Windows)
    #if canImport(Darwin)
        private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t?
    #else
        private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t
    #endif

    private func WIFEXITED(_ status: Int32) -> Bool {
        _WSTATUS(status) == 0
    }

    private func _WSTATUS(_ status: Int32) -> Int32 {
        status & 0x7F
    }

    private func WIFSIGNALED(_ status: Int32) -> Bool {
        (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7F)
    }

    private func WEXITSTATUS(_ status: Int32) -> Int32 {
        (status >> 8) & 0xFF
    }

    private func WTERMSIG(_ status: Int32) -> Int32 {
        status & 0x7F
    }

    /// Open the given pipe.
    private func open(pipe buffer: inout [Int32]) throws {
        let rv = pipe(&buffer)
        guard rv == 0 else {
            throw SystemError.pipe(rv)
        }
    }

    /// Close the given fd.
    private func close(fd: Int32) throws {
        func innerClose(_ fd: inout Int32) throws {
            let rv = close(fd)
            guard rv == 0 else {
                throw SystemError.close(rv)
            }
        }
        var innerFd = fd
        try innerClose(&innerFd)
    }

    extension AsyncProcess.Error: CustomStringConvertible {
        package var description: String {
            switch self {
            case .missingExecutableProgram(let program):
                "could not find executable for '\(program)'"
            case .workingDirectoryNotSupported:
                "workingDirectory is not supported in this platform"
            case .stdinUnavailable:
                "could not open stdin on this platform"
            }
        }
    }

    extension AsyncProcess.Error: CustomNSError {
        package var errorUserInfo: [String: Any] {
            [NSLocalizedDescriptionKey: self.description]
        }
    }

#endif  // #if os(Linux)
extension AsyncProcessResult.Error: CustomStringConvertible {
    package var description: String {
        switch self {
        case .systemError(let arguments, let underlyingError):
            return "error while executing `\(arguments.joined(separator: " "))`: \(underlyingError)"
        case .illegalUTF8Sequence:
            return "illegal UTF8 sequence output"
        case .nonZeroExit(let result):
            var str = ""
            switch result.exitStatus {
            case .terminated(let code):
                str.append(contentsOf: "terminated(\(code)): ")
            #if os(Windows)
                case .abnormal(let exception):
                    str.append(contentsOf: "abnormal(\(exception)): ")
            #else
                case .signalled(let signal):
                    str.append(contentsOf: "signalled(\(signal)): ")
            #endif
            }

            // Strip sandbox information from arguments to keep things pretty.
            var args = result.arguments
            // This seems a little fragile.
            if args.first == "sandbox-exec", args.count > 3 {
                args = args.suffix(from: 3).map { $0 }
            }
            str.append(contentsOf: args.map { $0.spm_shellEscaped() }.joined(separator: " "))

            // Include the output, if present.
            if let output = try? result.utf8Output() + result.utf8stderrOutput() {
                // We indent the output to keep it visually separated from everything else.
                let indentation = "    "
                str.append(contentsOf: " output:\n")
                str.append(contentsOf: indentation)
                str.append(
                    contentsOf: output.split(whereSeparator: { $0.isNewline })
                        .joined(separator: "\n\(indentation)"))
                if !output.hasSuffix("\n") {
                    str.append(contentsOf: "\n")
                }
            }

            return str
        }
    }
}  // #if os(Linux)
#if os(Windows)
    class WritableHandle: WritableByteStream {
        private var handle: HANDLE?

        package init(_ handle: HANDLE?) {
            self.handle = handle
        }

        package var position: Int {
            Int(SetFilePointer(self.handle, LONG(0), nil, DWORD(FILE_CURRENT)))
        }

        package func write(_ byte: UInt8) {
            var buffer = byte
            WriteFile(self.handle, &buffer, 1, nil, nil)
        }

        package func write(_ bytes: some Collection<UInt8>) {
            _ = bytes.withContiguousStorageIfAvailable { buffer in
                WriteFile(self.handle, buffer.baseAddress, DWORD(buffer.count), nil, nil)
            }
        }

        package func flush() {
            FlushFileBuffers(self.handle)
        }

        package func close() {
            CloseHandle(self.handle)
        }
    }

    extension String {
        var LPCWSTR: [UInt16] {
            return self.withCString(encodedAs: UTF16.self) { buffer in
                [UInt16](unsafeUninitializedCapacity: self.utf16.count + 1) {
                    wcscpy_s($0.baseAddress, $0.count, buffer)
                    $1 = $0.count
                }
            }
        }
    }

    // Taken from SCF
    private func quoteWindowsCommandLine(_ commandLine: [String]) -> String {
        func quoteWindowsCommandArg(arg: String) -> String {
            // Windows escaping, adapted from Daniel Colascione's "Everyone quotes
            // command line arguments the wrong way" - Microsoft Developer Blog
            if !arg.contains(where: { " \t\n\"".contains($0) }) {
                return arg
            }

            // To escape the command line, we surround the argument with quotes. However
            // the complication comes due to how the Windows command line parser treats
            // backslashes (\) and quotes (")
            //
            // - \ is normally treated as a literal backslash
            //     - e.g. foo\bar\baz => foo\bar\baz
            // - However, the sequence \" is treated as a literal "
            //     - e.g. foo\"bar => foo"bar
            //
            // But then what if we are given a path that ends with a \? Surrounding
            // foo\bar\ with " would be "foo\bar\" which would be an unterminated string

            // since it ends on a literal quote. To allow this case the parser treats:
            //
            // - \\" as \ followed by the " metachar
            // - \\\" as \ followed by a literal "
            // - In general:
            //     - 2n \ followed by " => n \ followed by the " metachar
            //     - 2n+1 \ followed by " => n \ followed by a literal "
            var quoted = "\""
            var unquoted = arg.unicodeScalars

            while !unquoted.isEmpty {
                guard let firstNonBackslash = unquoted.firstIndex(where: { $0 != "\\" }) else {
                    // String ends with a backslash e.g. foo\bar\, escape all the backslashes
                    // then add the metachar " below
                    let backslashCount = unquoted.count
                    quoted.append(String(repeating: "\\", count: backslashCount * 2))
                    break
                }
                let backslashCount = unquoted.distance(
                    from: unquoted.startIndex, to: firstNonBackslash)
                if unquoted[firstNonBackslash] == "\"" {
                    // This is  a string of \ followed by a " e.g. foo\"bar. Escape the
                    // backslashes and the quote
                    quoted.append(String(repeating: "\\", count: backslashCount * 2 + 1))
                    quoted.append(String(unquoted[firstNonBackslash]))
                } else {
                    // These are just literal backslashes
                    quoted.append(String(repeating: "\\", count: backslashCount))
                    quoted.append(String(unquoted[firstNonBackslash]))
                }
                // Drop the backslashes and the following character
                unquoted.removeFirst(backslashCount + 1)
            }
            quoted.append("\"")
            return quoted
        }
        return commandLine.map(quoteWindowsCommandArg).joined(separator: " ")
    }
#endif  // #if os(Linux)
