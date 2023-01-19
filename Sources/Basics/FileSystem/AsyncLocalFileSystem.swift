/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

#if swift(>=5.5.2)
import Foundation
import TSCBasic

/// Concrete FileSystem implementation which communicates with the local file system.
private actor LocalFileSystem: AsyncFileSystem {
    func isExecutableFile(_ path: AbsolutePath) -> Bool {
        // Our semantics doesn't consider directories.
        (self.isFile(path) || self.isSymlink(path)) && FileManager.default.isExecutableFile(atPath: path.pathString)
    }

    func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
        if followSymlink {
            return FileManager.default.fileExists(atPath: path.pathString)
        }
        return (try? FileManager.default.attributesOfItem(atPath: path.pathString)) != nil
    }

    func isDirectory(_ path: AbsolutePath) -> Bool {
        var isDirectory: ObjCBool = false
        let exists: Bool = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isFile(_ path: AbsolutePath) -> Bool {
        guard let path = try? resolveSymlinks(path) else {
            return false
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.pathString)
        return attrs?[.type] as? FileAttributeType == .typeRegular
    }

    func isSymlink(_ path: AbsolutePath) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.pathString)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    func isReadable(_ path: AbsolutePath) -> Bool {
        FileManager.default.isReadableFile(atPath: path.pathString)
    }

    func isWritable(_ path: AbsolutePath) -> Bool {
        FileManager.default.isWritableFile(atPath: path.pathString)
    }

    func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return FileInfo(attrs)
    }

    var currentWorkingDirectory: AbsolutePath? {
        let cwdStr = FileManager.default.currentDirectoryPath

#if _runtime(_ObjC)
        // The ObjC runtime indicates that the underlying Foundation has ObjC
        // interoperability in which case the return type of
        // `fileSystemRepresentation` is different from the Swift implementation
        // of Foundation.
        return try? AbsolutePath(validating: cwdStr)
#else
        let fsr: UnsafePointer<Int8> = cwdStr.fileSystemRepresentation
        defer { fsr.deallocate() }

        return try? AbsolutePath(String(cString: fsr))
#endif
    }

    func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
        guard isDirectory(path) else {
            throw FileSystemError(.notDirectory, path)
        }

        guard FileManager.default.changeCurrentDirectoryPath(path.pathString) else {
            throw FileSystemError(.couldNotChangeDirectory, path)
        }
    }

    var homeDirectory: AbsolutePath {
        get throws {
            return try AbsolutePath(validating: NSHomeDirectory())
        }
    }

    var cachesDirectory: AbsolutePath? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.flatMap { try? AbsolutePath(validating: $0.path) }
    }

    var tempDirectory: AbsolutePath {
        get throws {
            let override = ProcessEnv.vars["TMPDIR"] ?? ProcessEnv.vars["TEMP"] ?? ProcessEnv.vars["TMP"]
            if let path = override.flatMap({ try? AbsolutePath(validating: $0) }) {
                return path
            }
            return try AbsolutePath(validating: NSTemporaryDirectory())
        }
    }

    func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
#if canImport(Darwin)
        return try FileManager.default.contentsOfDirectory(atPath: path.pathString)
#else
        do {
            return try FileManager.default.contentsOfDirectory(atPath: path.pathString)
        } catch let error as NSError {
            // Fixup error from corelibs-foundation.
            if error.code == CocoaError.fileReadNoSuchFile.rawValue, !error.userInfo.keys.contains(NSLocalizedDescriptionKey) {
                var userInfo = error.userInfo
                userInfo[NSLocalizedDescriptionKey] = "The folder “\(path.basename)” doesn’t exist."
                throw NSError(domain: error.domain, code: error.code, userInfo: userInfo)
            }
            throw error
        }
#endif
    }

    func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
        // Don't fail if path is already a directory.
        if isDirectory(path) { return }

        try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: recursive, attributes: [:])
    }

    func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
        let destString = relative ? destination.relative(to: path.parentDirectory).pathString : destination.pathString
        try FileManager.default.createSymbolicLink(atPath: path.pathString, withDestinationPath: destString)
    }

    func readFileContents(_ path: AbsolutePath) throws -> ByteString {
        // Open the file.
        let fp = fopen(path.pathString, "rb")
        if fp == nil {
            throw FileSystemError(errno: errno, path)
        }
        defer { fclose(fp) }

        // Read the data one block at a time.
        let data = BufferedOutputByteStream()
        var tmpBuffer = [UInt8](repeating: 0, count: 1 << 12)
        while true {
            let n = fread(&tmpBuffer, 1, tmpBuffer.count, fp)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError(.ioError(code: errno), path)
            }
            if n == 0 {
                let errno = ferror(fp)
                if errno != 0 {
                    throw FileSystemError(.ioError(code: errno), path)
                }
                break
            }
            data <<< tmpBuffer[0..<n]
        }

        return data.bytes
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
        // Open the file.
        let fp = fopen(path.pathString, "wb")
        if fp == nil {
            throw FileSystemError(errno: errno, path)
        }
        defer { fclose(fp) }

        // Write the data in one chunk.
        var contents = bytes.contents
        while true {
            let n = fwrite(&contents, 1, contents.count, fp)
            if n < 0 {
                if errno == EINTR { continue }
                throw FileSystemError(.ioError(code: errno), path)
            }
            if n != contents.count {
                throw FileSystemError(.mismatchedByteCount(expected: contents.count, actual: n), path)
            }
            break
        }
    }

    func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
        // Perform non-atomic writes using the fast path.
        if !atomically {
            return try writeFileContents(path, bytes: bytes)
        }

        try bytes.withData {
            try $0.write(to: URL(fileURLWithPath: path.pathString), options: .atomic)
        }
    }

    func removeFileTree(_ path: AbsolutePath) throws {
        do {
            try FileManager.default.removeItem(atPath: path.pathString)
        } catch let error as NSError {
            // If we failed because the directory doesn't actually exist anymore, ignore the error.
            if !(error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError) {
                throw error
            }
        }
    }

    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
        guard exists(path) else { return }
        func setMode(path: String) throws {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            // Skip if only files should be changed.
            if options.contains(.onlyFiles) && attrs[.type] as? FileAttributeType != .typeRegular {
                return
            }

            // Compute the new mode for this file.
            let currentMode = attrs[.posixPermissions] as! Int16
            let newMode = mode.setMode(currentMode)
            guard newMode != currentMode else { return }
            try FileManager.default.setAttributes([.posixPermissions : newMode],
                                                  ofItemAtPath: path)
        }

        try setMode(path: path.pathString)
        guard isDirectory(path) else { return }

        guard let traverse = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path.pathString),
            includingPropertiesForKeys: nil) else {
                throw FileSystemError(.noEntry, path)
            }

        if !options.contains(.recursive) {
            traverse.skipDescendants()
        }

        while let path = traverse.nextObject() {
            try setMode(path: (path as! URL).path)
        }
    }

    func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        guard exists(sourcePath) else { throw FileSystemError(.noEntry, sourcePath) }
        guard !exists(destinationPath)
        else { throw FileSystemError(.alreadyExistsAtDestination, destinationPath) }
        try FileManager.default.copyItem(at: sourcePath.asURL, to: destinationPath.asURL)
    }

    func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
        guard exists(sourcePath) else { throw FileSystemError(.noEntry, sourcePath) }
        guard !exists(destinationPath)
        else { throw FileSystemError(.alreadyExistsAtDestination, destinationPath) }
        try FileManager.default.moveItem(at: sourcePath.asURL, to: destinationPath.asURL)
    }

    func withLock<T>(on path: AbsolutePath, type: FileLock.LockType = .exclusive, _ body: () throws -> T) throws -> T {
        try FileLock.withLock(fileToLock: path, type: type, body: body)
    }
}
#endif
