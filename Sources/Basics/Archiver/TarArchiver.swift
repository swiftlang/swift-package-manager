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
import struct Dispatch.DispatchTime
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

    /// Creates a `TarArchiver` that runs `tarCommand` instead of the platform's `tar`. For testing.
    internal init(fileSystem: FileSystem, cancellator: Cancellator?, tarCommand: String) {
        self.fileSystem = fileSystem
        self.cancellator = cancellator ?? Cancellator(observabilityScope: .none)
        self.tarCommand = tarCommand
    }

    /// The `tar` executable to run: looked up in `PATH` unless the command is a path.
    private var executable: Subprocess.Executable {
        #if os(Windows)
        return .path(FilePath(self.tarCommand))
        #else
        return self.tarCommand.contains("/") ? .path(FilePath(self.tarCommand)) : .name(self.tarCommand)
        #endif
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

        let executable = self.executable

        let result = try await self.cancellator.withCancellable(name: self.tarCommand) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments([
                    "xf", archivePath.pathString, "-C", destinationPath.pathString,
                ]),
                platformOptions: .cancellable,
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        }
        guard result.terminationStatus.isSuccess else {
            throw StringError(result.standardOutput + result.standardError)
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

        let executable = self.executable

        let result = try await self.cancellator.withCancellable(name: self.tarCommand) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments(["acf", destinationPath.pathString] + paths.map(\.pathString)),
                workingDirectory: FilePath(parent.pathString),
                platformOptions: .cancellable,
                output: .string(limit: .max),
                error: .string(limit: .max)
            )
        }
        guard result.terminationStatus.isSuccess else {
            throw StringError(result.standardOutput + result.standardError)
        }
    }

    public func validate(path: AbsolutePath) async throws -> Bool {
        guard self.fileSystem.exists(path) else {
            throw FileSystemError(.noEntry, path.underlying)
        }

        let executable = self.executable

        let result = try await self.cancellator.withCancellable(name: self.tarCommand) {
            try await Subprocess.run(
                executable,
                arguments: Subprocess.Arguments(["tf", path.pathString]),
                platformOptions: .cancellable,
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
