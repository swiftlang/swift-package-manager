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
#if USE_IMPL_ONLY_IMPORTS
@_implementationOnly import Subprocess
#if canImport(System)
@_implementationOnly import System
#else
@_implementationOnly import SystemPackage
#endif
#else
internal import Subprocess
#if canImport(System)
internal import System
#else
internal import SystemPackage
#endif
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
        to destinationPath: AbsolutePath
    ) async throws {
        guard self.fileSystem.exists(archivePath) else {
            throw FileSystemError(.noEntry, archivePath.underlying)
        }

        guard self.fileSystem.isDirectory(destinationPath) else {
            throw FileSystemError(.notDirectory, destinationPath.underlying)
        }

        let result = try await self.cancellator.withCancellable(name: self.unzip) {
            try await Subprocess.run(
                Subprocess.Executable.name(self.unzip),
                arguments: Subprocess.Arguments([
                    archivePath.pathString, "-d", destinationPath.pathString,
                ]),
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        }
        guard result.terminationStatus.isSuccess else {
            throw StringError((result.standardOutput ?? "") + (result.standardError ?? ""))
        }
    }

    public func compress(
        paths: [RelativePath],
        from parent: AbsolutePath,
        to destinationPath: AbsolutePath
    ) async throws {
        guard self.fileSystem.isDirectory(parent) else {
            throw FileSystemError(.notDirectory, parent.underlying)
        }

        #if os(FreeBSD)
        // On FreeBSD, the unzip command is available in base but not the zip command.
        // Therefore; we use libarchive(bsdtar) to produce the ZIP archive instead.
        let executable = Subprocess.Executable.name(self.tar)
        let args = ["-c", "--format", "zip", "-f", destinationPath.pathString] + paths.map(\.pathString)
        let workingDirectory: FilePath? = FilePath(parent.pathString)
        #else
        // This is to work around `swift package-registry publish` tool failing on
        // Amazon Linux 2 due to it having an earlier Glibc version (rdar://116370323)
        // and therefore posix_spawn_file_actions_addchdir_np is unavailable.
        // Instead of passing `workingDirectory` param to TSC.Process, which will trigger
        // SPM_posix_spawn_file_actions_addchdir_np_supported check, we shell out and
        // do `cd` explicitly before `zip`.
        let executable = Subprocess.Executable.path(FilePath("/bin/sh"))
        let inputs = paths.map(\.pathString).joined(separator: " ")
        let command = "cd \(parent.underlying.pathString) && \(self.zip) -ry \(destinationPath.pathString) \(inputs)"
        let args = ["-c", command]
        let workingDirectory: FilePath? = nil
        #endif

        let result = try await self.cancellator.withCancellable(name: self.zip) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments(args),
                workingDirectory: workingDirectory,
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        }
        guard result.terminationStatus.isSuccess else {
            throw StringError((result.standardOutput ?? "") + (result.standardError ?? ""))
        }
    }

    public func validate(path: AbsolutePath) async throws -> Bool {
        guard self.fileSystem.exists(path) else {
            throw FileSystemError(.noEntry, path.underlying)
        }

        let result = try await self.cancellator.withCancellable(name: self.unzip) {
            try await Subprocess.run(
                Subprocess.Executable.name(self.unzip),
                arguments: Subprocess.Arguments(["-t", path.pathString]),
                output: .discarded,
                error: .discarded
            )
        }
        return result.terminationStatus.isSuccess
    }

    public func cancel(deadline: DispatchTime) throws {
        try self.cancellator.cancel(deadline: deadline)
    }
}
