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

import Foundation
import class Dispatch.DispatchQueue
import struct Dispatch.DispatchTime
import struct TSCBasic.FileSystemError
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

#if os(Windows)
import WinSDK
#endif

/// An `Archiver` that handles Tar archives using the command-line `tar` tool.
public struct TarArchiver: Archiver {
#if os(Windows)
    public let supportedExtensions: Set<String> = ["tar", "tar.gz", "zip"]
#else
    public let supportedExtensions: Set<String> = ["tar", "tar.gz"]
#endif

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Helper for cancelling in-flight requests
    private let cancellator: Cancellator

    /// The underlying command
    internal let tarCommand: String

    /// Creates a `TarArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file system to used by the `TarArchiver`.
    ///   - cancellator: Cancellation handler
    public init(fileSystem: FileSystem, cancellator: Cancellator? = .none) {
        self.fileSystem = fileSystem
        self.cancellator = cancellator ?? Cancellator(observabilityScope: .none)

#if os(Windows)
        let command = "tar.exe"
        if let system32 = URL.system32 {
            // Use the Windows tar which is based on libarchive
            self.tarCommand = system32.appending(component: command).path
        } else {
            self.tarCommand = command
        }
#else
        self.tarCommand = "tar"
#endif
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

            let process = AsyncProcess(
                arguments: [self.tarCommand, "xf", archivePath.pathString, "-C", destinationPath.pathString]
            )

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

        #if os(Windows)
        let executable = Subprocess.Executable.path(FilePath(self.tarCommand))
        #else
        let executable = Subprocess.Executable.name(self.tarCommand)
        #endif

        let outcome = try await self.cancellator.withCancellable(name: self.tarCommand) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments(["acf", destinationPath.pathString, directory.basename]),
                workingDirectory: FilePath(directory.parentDirectory.pathString),
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

            let process = AsyncProcess(arguments: [self.tarCommand, "tf", path.pathString])
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
