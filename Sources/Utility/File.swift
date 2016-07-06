/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public enum FopenMode: String {
    case read = "r"
    case write = "w"
}

public func fopen(_ path: String, mode: FopenMode = .read) throws -> FileHandle {
    let handle: FileHandle!
    switch mode {
    case .read: handle = FileHandle(forReadingAtPath: path)
    case .write:
        guard FileManager.default.createFile(atPath: path, contents: nil) else {
            throw Error.couldNotCreateFile(path: path)
        }
        handle = FileHandle(forWritingAtPath: path)
    }
    guard handle != nil else {
        throw Error.fileDoesNotExist(path: path)
    }
    return handle
}

public func fopen<T>(_ path: String..., mode: FopenMode = .read, body: (FileHandle) throws -> T) throws -> T {
    let fp = try fopen(Path.join(path), mode: mode)
    defer { fp.closeFile() }
    return try body(fp)
}

public func fputs(_ string: String, _ handle: FileHandle) throws {
    guard let data = string.data(using: .utf8) else {
        throw Error.unicodeEncodingError
    }

    handle.write(data)
}

public func fputs(_ bytes: [UInt8], _ handle: FileHandle) throws {
    handle.write(Data(bytes: bytes))
}

extension FileHandle {
    public func readFileContents() throws -> String {
        guard let contents = String(data: readDataToEndOfFile(), encoding: .utf8) else {
            throw Error.unicodeDecodingError
        }
        return contents
    }
}
