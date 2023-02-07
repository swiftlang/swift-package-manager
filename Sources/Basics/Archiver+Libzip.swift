//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Dispatch
import struct Foundation.Data
import TSCBasic

@_implementationOnly import SPMLibzip

/// An `Archiver` that handles ZIP archives using the libzip library
public struct LibzipArchiver: Archiver, Cancellable {
    public var supportedExtensions: Set<String> { ["zip"] }

    /// The file-system implementation used for various file-system operations and checks.
    private let fileSystem: FileSystem

    /// Helper for cancelling in-flight requests
    private let cancellator: Cancellator

    /// Creates a `ZipArchiver`.
    ///
    /// - Parameters:
    ///   - fileSystem: The file-system to used by the `ZipArchiver`.
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

            let extractor = Libzip.Extractor(
                archivePath: archivePath,
                destinationPath: destinationPath,
                fileSystem: self.fileSystem
            )
            guard let cancellationKey = self.cancellator.register(
                name: "zipfile extractor for '\(archivePath)'",
                handler: extractor
            ) else {
                throw StringError("cancellation")
            }

            DispatchQueue.sharedConcurrent.async {
                defer { self.cancellator.deregister(cancellationKey) }
                completion(.init(catching: {
                    try extractor.extract()
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

            let compressor = Libzip.Compressor(
                directory: directory,
                destinationPath: destinationPath,
                fileSystem: self.fileSystem
            )
            guard let cancellationKey = self.cancellator.register(
                name: "zipfile compressor for '\(directory)'",
                handler: compressor
            ) else {
                throw StringError("cancellation")
            }

            DispatchQueue.sharedConcurrent.async {
                defer { self.cancellator.deregister(cancellationKey) }
                completion(.init(catching: {
                    try compressor.compress()
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

            let validator = Libzip.Validator(
                archivePath: path,
                fileSystem: self.fileSystem
            )

            return try completion(.success(validator.validate()))
        } catch {
            return completion(.failure(error))
        }
    }

    public func cancel(deadline: DispatchTime) throws {
        try self.cancellator.cancel(deadline: deadline)
    }
}

enum Libzip {
    struct Extractor: Cancellable {
        let archivePath: AbsolutePath
        let destinationPath: AbsolutePath
        let fileSystem: FileSystem
        let cancelled = ThreadSafeBox(false)

        init(
            archivePath: AbsolutePath,
            destinationPath: AbsolutePath,
            fileSystem: FileSystem
        ) {
            self.archivePath = archivePath
            self.destinationPath = destinationPath
            self.fileSystem = fileSystem
        }

        func extract() throws {
            let archive = try ReadonlyZipArchive(path: self.archivePath)
            for entry in try archive.entries() {
                guard !self.cancelled.get(default: false) else {
                    continue
                }
                guard let entryName = entry.name else {
                    print("** skipping entry \(entry.index), unknown name")
                    continue
                }
                print("** extracting \(entryName)")
                let entryDestinationPath = try destinationPath.appending(RelativePath(validating: entryName))
                // FIXME: windows?
                if entryName.suffix(1) == "/" {
                    try fileSystem.createDirectory(entryDestinationPath)
                } else {
                    let content = try entry.readAll()
                    try fileSystem.writeFileContents(entryDestinationPath, data: content)
                }
            }
        }

        func cancel(deadline: DispatchTime) throws {
            self.cancelled.put(true)
        }
    }

    struct Compressor: Cancellable {
        let directory: AbsolutePath
        let destinationPath: AbsolutePath
        let fileSystem: FileSystem
        let cancelled = ThreadSafeBox(false)

        init(directory: AbsolutePath, destinationPath: AbsolutePath, fileSystem: FileSystem) {
            self.directory = directory
            self.destinationPath = destinationPath
            self.fileSystem = fileSystem
        }

        func compress() throws {
            let archive = try WritableZipArchive(path: self.destinationPath)
            // top level
            try archive.addDirectory(name: self.directory.basename)
            // recurse into directories
            try compressDirectory(root: self.directory, directory: self.directory, archive: archive)
            try archive.save()

            func compressDirectory(root: AbsolutePath, directory: AbsolutePath, archive: WritableZipArchive) throws {
                let content = try self.fileSystem.getDirectoryContents(directory)
                for entry in content {
                    let absolutePath = directory.appending(component: entry)
                    let relativePath = absolutePath.relative(to: root)
                    let entryArchivePath = try RelativePath(validating: root.basename).appending(relativePath)
                    if self.fileSystem.isDirectory(absolutePath) {
                        try archive.addDirectory(name: entryArchivePath.pathString)
                        try compressDirectory(root: root, directory: absolutePath, archive: archive)
                    } else if self.fileSystem.isFile(absolutePath) {
                        // let data: Data = try fileSystem.readFileContents(entryPath)
                        // let source = try ZipSource(data: data)
                        let source = try ZipSource(archive: archive, path: absolutePath.pathString)
                        try archive.addFile(name: entryArchivePath.pathString, source: source)
                    } else {
                        throw StringError("\(absolutePath) is neither a file not a directory")
                    }
                }
            }
        }

        func cancel(deadline: DispatchTime) throws {
            self.cancelled.put(true)
        }
    }

    struct Validator {
        let archivePath: AbsolutePath
        let fileSystem: FileSystem
        let cancelled = ThreadSafeBox(false)

        init(
            archivePath: AbsolutePath,
            fileSystem: FileSystem
        ) {
            self.archivePath = archivePath
            self.fileSystem = fileSystem
        }

        func validate() throws -> Bool {
            do {
                _ = try ReadonlyZipArchive(path: self.archivePath)
                return true
            } catch is LibzipError {
                return false
            }
        }
    }

    final class WritableZipArchive {
        var rawPointer: OpaquePointer

        init(path: AbsolutePath) throws {
            var status: Int32 = ZIP_ER_OK
            guard let handle = zip_open(path.pathString, ZIP_CREATE | ZIP_EXCL, &status) else {
                throw LibzipError(code: status)
            }
            try Libzip.validateLibzipStatus(status)
            self.rawPointer = handle
        }

        func save() throws {
            let status = zip_close(self.rawPointer)
            try Libzip.validateLibzipStatus(status)
        }

        public func addDirectory(name: String) throws {
            zip_dir_add(self.rawPointer, name, ZIP_FL_ENC_UTF_8)
        }

        public func addFile(name: String, source: ZipSource) throws {
            zip_file_add(self.rawPointer, name, source.rawPointer, ZIP_FL_ENC_UTF_8)
            // not sure why this is needed
            source.keep()
        }
    }

    final class ZipSource {
        let rawPointer: OpaquePointer

        init(rawPointer: OpaquePointer) {
            self.rawPointer = rawPointer
        }

        convenience init(archive: WritableZipArchive, path: String) throws {
            guard let rawPointer = zip_source_file(archive.rawPointer, path, 0, 0) else {
                throw StringError("Failed opening zip source from '\(path)'")
            }
            self.init(rawPointer: rawPointer)
        }

        func keep() {
            zip_source_keep(self.rawPointer)
        }

        deinit {
            zip_source_free(self.rawPointer)
        }
    }

    final class ReadonlyZipArchive {
        var rawPointer: OpaquePointer

        init(path: AbsolutePath) throws {
            var status: Int32 = ZIP_ER_OK
            guard let handle = zip_open(path.pathString, ZIP_RDONLY, &status) else {
                throw LibzipError(code: status)
            }
            try Libzip.validateLibzipStatus(status)
            self.rawPointer = handle
        }

        deinit {
            zip_discard(self.rawPointer)
        }

        func entries() throws -> Entries {
            try Entries(archive: self)
        }

        class Entries: RandomAccessCollection {
            let archive: ReadonlyZipArchive
            var startIndex: Int
            var endIndex: Int = 0

            init(archive: ReadonlyZipArchive) throws {
                self.archive = archive
                self.startIndex = 0
                let result = zip_get_num_entries(archive.rawPointer, 0)
                // FIXME: cast
                self.endIndex = Int(result)
            }

            subscript(position: Int) -> Entry {
                // FIXME: force try
                try! Entry(archive: self.archive, index: position)
            }
        }

        struct Entry {
            let archive: ReadonlyZipArchive
            var index: Int
            let stat: Stat

            init(archive: ReadonlyZipArchive, index: Int) throws {
                self.archive = archive
                self.index = index

                var stat = zip_stat()
                // FIXME: cast
                let status = zip_stat_index(archive.rawPointer, UInt64(index), 0, &stat)
                try Libzip.validateLibzipStatus(status)
                self.stat = Stat(underlying: stat)
            }

            var name: String? {
                self.stat.name
            }

            var size: UInt64 {
                self.stat.size
            }

            var compressedSize: UInt64 {
                self.stat.compressedSize
            }

            func readAll() throws -> Data {
                var buffer = Data()
                try self.read {
                    buffer.append($0)
                }
                return buffer
            }

            // FIXME: optimize this (eg read + write at the same time)
            func read(handler: (Data) throws -> Void) throws {
                // FIXME: cast
                guard let readerHandler = zip_fopen_index(self.archive.rawPointer, UInt64(self.index), 0) else {
                    throw StringError("failed opening archive entry \(self.index)")
                }

                let reader = Reader(rawPointer: readerHandler)
                try reader.read(maxBytes: self.size, handler: handler)
            }

            final class Reader {
                var rawPointer: OpaquePointer

                init(rawPointer: OpaquePointer) {
                    self.rawPointer = rawPointer
                }

                deinit {
                    let status = zip_fclose(self.rawPointer)
                    assert(status == ZIP_ER_OK, "Failed to close reader, error code: \(status)")
                }

                // FIXME: optimize this, add progress handler
                func read(maxBytes: UInt64, handler: (Data) throws -> Void) throws {
                    let chunkSize = 1024
                    var totalRead: Int64 = 0
                    while totalRead < maxBytes {
                        var buffer = Data(count: chunkSize)
                        let readBytes = buffer.withUnsafeMutableBytes { buffer in
                            // FIXME: cast
                            zip_fread(self.rawPointer, buffer, UInt64(chunkSize))
                        }

                        guard readBytes > 0 else {
                            break
                        }

                        totalRead += readBytes

                        // FIXME: cast
                        let chunk = Data(buffer.subdata(in: 0 ..< Int(readBytes)))
                        try handler(chunk)
                    }
                }
            }

            struct Stat {
                var underlying: zip_stat

                init(underlying: zip_stat) {
                    self.underlying = underlying
                }

                var index: UInt64 {
                    self.underlying.index
                }

                var name: String? {
                    self.underlying.name.flatMap(String.init(cString:))
                }

                var size: UInt64 {
                    self.underlying.size
                }

                var compressedSize: UInt64 {
                    self.underlying.comp_size
                }
            }
        }
    }

    fileprivate static func validateLibzipStatus(_ code: Int32) throws {
        switch code {
        case ZIP_ER_OK:
            return
        case let code:
            throw LibzipError(code: code)
        }
    }

    struct LibzipError: Error, CustomStringConvertible {
        let underlying: zip_error_t

        init(underlying: zip_error_t) {
            self.init(underlying: underlying)
        }

        init(code: Int32) {
            self.underlying = zip_error_t(zip_err: code, sys_err: 0, str: nil)
        }

        var description: String {
            var underlying = self.underlying
            let error = zip_error_strerror(&underlying)
            return String(cString: error)
        }
    }
}
