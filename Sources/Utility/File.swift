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

public func fopen(_ path: String, mode: FopenMode = .read) throws -> NSFileHandle {
    let handle: NSFileHandle!
    switch mode {
    case .read: handle = NSFileHandle(forReadingAtPath: path)
    case .write:
        #if os(OSX) || os(iOS)
            guard NSFileManager.default.createFile(atPath: path, contents: nil) else {
                throw Error.couldNotCreateFile(path: path)
            }
        #else
            guard NSFileManager.default.createFile(atPath: path, contents: nil) else {
                throw Error.couldNotCreateFile(path: path)
            }
        #endif
        handle = NSFileHandle(forWritingAtPath: path)
    }
    guard handle != nil else {
        throw Error.fileDoesNotExist(path: path)
    }
    return handle
}

public func fopen<T>(_ path: String..., mode: FopenMode = .read, body: (NSFileHandle) throws -> T) throws -> T {
    let fp = try fopen(Path.join(path), mode: mode)
    defer { fp.closeFile() }
    return try body(fp)
}

public func fputs(_ string: String, _ handle: NSFileHandle) throws {
    guard let data = string.data(using: NSUTF8StringEncoding) else {
        throw Error.unicodeEncodingError
    }

    #if os(OSX) || os(iOS)
        handle.write(data)
    #else
        handle.writeData(data)
    #endif
}

public func fputs(_ bytes: [UInt8], _ handle: NSFileHandle) throws {
    var bytes = bytes
    let data = NSData(bytes: &bytes, length: bytes.count)

    #if os(OSX) || os(iOS)
        handle.write(data)
    #else
        handle.writeData(data)
    #endif
}


extension NSFileHandle: Sequence {
    public func enumerate(separatedBy separator: String = "\n") throws -> IndexingIterator<[String]> {
        guard let contents = String(data: readDataToEndOfFile(), encoding: NSUTF8StringEncoding) else {
            throw Error.unicodeDecodingError
        }

        if contents == "" {
            return [].makeIterator()
        }

        return contents.components(separatedBy: separator).makeIterator()
    }

    public func makeIterator() -> IndexingIterator<[String]> {
        guard let iterator = try? enumerate() else {
            return [].makeIterator()
        }
        return iterator
    }
}
