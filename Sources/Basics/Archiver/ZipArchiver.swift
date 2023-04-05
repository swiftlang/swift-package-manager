//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic
import Dispatch

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
                throw FileSystemError(.noEntry, archivePath)
            }

            guard self.fileSystem.isDirectory(destinationPath) else {
                throw FileSystemError(.notDirectory, destinationPath)
            }

#if os(Windows)
            let process = TSCBasic.Process(arguments: ["tar.exe", "xf", archivePath.pathString, "-C", destinationPath.pathString])
#else
            let process = TSCBasic.Process(arguments: ["unzip", archivePath.pathString, "-d", destinationPath.pathString])
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
                throw FileSystemError(.notDirectory, directory)
            }

#if os(Windows)
            let process = TSCBasic.Process(
                // FIXME: are these the right arguments?
                arguments: ["tar.exe", "-a", "-c", "-f", destinationPath.pathString, directory.basename],
                workingDirectory: directory.parentDirectory
            )
#else
            let process = TSCBasic.Process(
                arguments: ["zip", "-r", destinationPath.pathString, directory.basename],
                workingDirectory: directory.parentDirectory
            )
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

    public func validate(path: AbsolutePath, completion: @escaping (Result<Bool, Error>) -> Void) {
        do {
            guard self.fileSystem.exists(path) else {
                throw FileSystemError(.noEntry, path)
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
