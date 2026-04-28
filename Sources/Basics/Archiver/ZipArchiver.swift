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
import struct TSCBasic.FileSystemError
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// An `Archiver` that handles ZIP archives using the command-line `zip` and `unzip` tools.
public struct ZipArchiver: Archiver, Cancellable {
#if os(Windows)
    // On Windows zip is handled by the TarArchiver with the system32 tar.exe command
    public var supportedExtensions: Set<String> { [] }
#else
    public var supportedExtensions: Set<String> { ["zip"] }
#endif

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Helper for cancelling in-flight requests
    private let cancellator: Cancellator

    internal let unzip = "unzip"
    internal let zip = "zip"

    #if os(FreeBSD)
        internal let tar = "tar"
    #endif

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
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        do {
            guard self.fileSystem.exists(archivePath) else {
                throw FileSystemError(.noEntry, archivePath.underlying)
            }

            guard self.fileSystem.isDirectory(destinationPath) else {
                throw FileSystemError(.notDirectory, destinationPath.underlying)
            }

            let process = AsyncProcess(arguments: [
                self.unzip, archivePath.pathString, "-d", destinationPath.pathString,
            ])
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
        to destinationPath: AbsolutePath
    ) async throws {
        guard self.fileSystem.isDirectory(directory) else {
            throw FileSystemError(.notDirectory, directory.underlying)
        }

        #if os(FreeBSD)
        let executable = Subprocess.Executable.name(self.tar)
        let args = ["-c", "--format", "zip", "-f", destinationPath.pathString, directory.basename]
        let workingDirectory: FilePath? = FilePath(directory.parentDirectory.pathString)
        #else
        let executable = Subprocess.Executable.path(FilePath("/bin/sh"))
        let args = ["-c", "cd \(directory.parentDirectory.underlying.pathString) && \(self.zip) -ry \(destinationPath.pathString) \(directory.basename)"]
        let workingDirectory: FilePath? = nil
        #endif

        let outcome = try await self.cancellator.withCancellable(name: self.zip) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments(args),
                workingDirectory: workingDirectory,
                error: .combinedWithOutput
            ) { _, outputSequence -> String in
                var output = ""
                for try await buffer in outputSequence {
                    buffer.withUnsafeBytes { output += String(decoding: $0, as: UTF8.self) }
                }
                return output
            }
        }
        guard outcome.terminationStatus.isSuccess else {
            throw StringError(outcome.value)
        }
    }

    public func validate(path: AbsolutePath, completion: @escaping @Sendable (Result<Bool, Error>) -> Void) {
        do {
            guard self.fileSystem.exists(path) else {
                throw FileSystemError(.noEntry, path.underlying)
            }

            let process = AsyncProcess(arguments: [self.unzip, "-t", path.pathString])
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
