//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import class Foundation.Pipe
import class Foundation.Process
import struct Foundation.URL
import struct TSCBasic.FileSystemError
import class TSCBasic.Process

#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import TSCclibc
#else
import TSCclibc
#endif

/// An `Archiver` that handles ZIP archives using the command-line `zip` and `unzip` tools.
public struct ZipArchiver: Archiver, Cancellable {
    public var supportedExtensions: Set<String> { ["zip"] }

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Helper for cancelling in-flight requests
    private let cancellator: Cancellator

    /// Creates a `ZipArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file-system to be used by the `ZipArchiver`.
    ///   - cancellator: Cancellation handler
    public init(fileSystem: FileSystem, cancellator: Cancellator? = .none) {
        self.fileSystem = fileSystem
        self.cancellator = cancellator ?? Cancellator(observabilityScope: .none)
    }

    public func extract(
        from archivePath: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            guard self.fileSystem.exists(archivePath) else {
                throw FileSystemError(.noEntry, archivePath.underlying)
            }

            guard self.fileSystem.isDirectory(destinationPath) else {
                throw FileSystemError(.notDirectory, destinationPath.underlying)
            }

            #if os(Windows)
            let process = TSCBasic
                .Process(arguments: ["tar.exe", "xf", archivePath.pathString, "-C", destinationPath.pathString])
            #else
            let process = TSCBasic
                .Process(arguments: ["unzip", archivePath.pathString, "-d", destinationPath.pathString])
            #endif
            guard let registrationKey = self.cancellator.register(process) else {
                throw CancellationError.failedToRegisterProcess(process)
            }

            DispatchQueue.sharedConcurrent.async {
                defer { self.cancellator.deregister(registrationKey) }
                completion(.init(catching: {
                    try process.launch()
                    let processResult = try process.waitUntilExit()
                    guard processResult.exitStatus == .terminated(code: 0) else {
                        throw try StringError(processResult.utf8stderrOutput())
                    }
                }))
            }
        } catch {
            return completion(.failure(error))
        }
    }

    public func compress(
        directory: AbsolutePath,
        to destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            guard self.fileSystem.isDirectory(directory) else {
                throw FileSystemError(.notDirectory, directory.underlying)
            }

            #if os(Windows)
            let process = TSCBasic.Process(
                // FIXME: are these the right arguments?
                arguments: ["tar.exe", "-a", "-c", "-f", destinationPath.pathString, directory.basename],
                workingDirectory: directory.parentDirectory.underlying
            )
            try self.launchAndWait(process: process, completion: completion)
            #elseif os(Linux)
            // This is to work around `swift package-registry publish` tool failing on
            // Amazon Linux 2 due to it having an earlier Glibc version (rdar://116370323)
            // and therefore posix_spawn_file_actions_addchdir_np is unavailable.
            // Instead of TSC.Process, we shell out to Foundation.Process and do `cd`
            // explicitly before `zip`.
            if SPM_posix_spawn_file_actions_addchdir_np_supported() {
                try self.compress_zip(
                    directory: directory,
                    destinationPath: destinationPath,
                    completion: completion
                )
            } else {
                let process = Foundation.Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [
                    "-c",
                    "cd \(directory.parentDirectory.underlying.pathString) && zip -r \(destinationPath.pathString) \(directory.basename)",
                ]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try self.launchAndWait(
                    process: process,
                    stdoutPipe: stdoutPipe,
                    stderrPipe: stderrPipe,
                    completion: completion
                )
            }
            #else
            try self.compress_zip(
                directory: directory,
                destinationPath: destinationPath,
                completion: completion
            )
            #endif
        } catch {
            return completion(.failure(error))
        }
    }

    private func compress_zip(
        directory: AbsolutePath,
        destinationPath: AbsolutePath,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        let process = TSCBasic.Process(
            arguments: ["zip", "-r", destinationPath.pathString, directory.basename],
            workingDirectory: directory.parentDirectory.underlying
        )
        try self.launchAndWait(process: process, completion: completion)
    }

    private func launchAndWait(
        process: TSCBasic.Process,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        guard let registrationKey = self.cancellator.register(process) else {
            throw CancellationError.failedToRegisterProcess(process)
        }

        DispatchQueue.sharedConcurrent.async {
            defer { self.cancellator.deregister(registrationKey) }
            completion(.init(catching: {
                try process.launch()
                let processResult = try process.waitUntilExit()
                guard processResult.exitStatus == .terminated(code: 0) else {
                    throw try StringError(processResult.utf8stderrOutput())
                }
            }))
        }
    }

    #if os(Linux)
    private func launchAndWait(
        process: Foundation.Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        completion: @escaping (Result<Void, Error>) -> Void
    ) throws {
        guard let registrationKey = self.cancellator.register(process) else {
            throw CancellationError.failedToRegisterProcess(process)
        }

        DispatchQueue.sharedConcurrent.async {
            defer { self.cancellator.deregister(registrationKey) }
            completion(.init(catching: {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    throw StringError(String(decoding: stderr, as: UTF8.self))
                }
            }))
        }
    }
    #endif

    public func validate(path: AbsolutePath, completion: @escaping (Result<Bool, Error>) -> Void) {
        do {
            guard self.fileSystem.exists(path) else {
                throw FileSystemError(.noEntry, path.underlying)
            }

            #if os(Windows)
            let process = TSCBasic.Process(arguments: ["tar.exe", "tf", path.pathString])
            #else
            let process = TSCBasic.Process(arguments: ["unzip", "-t", path.pathString])
            #endif
            guard let registrationKey = self.cancellator.register(process) else {
                throw CancellationError.failedToRegisterProcess(process)
            }

            DispatchQueue.sharedConcurrent.async {
                defer { self.cancellator.deregister(registrationKey) }
                completion(.init(catching: {
                    try process.launch()
                    let processResult = try process.waitUntilExit()
                    return processResult.exitStatus == .terminated(code: 0)
                }))
            }
        } catch {
            return completion(.failure(error))
        }
    }

    public func cancel(deadline: DispatchTime) throws {
        try self.cancellator.cancel(deadline: deadline)
    }
}
