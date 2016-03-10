/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct libc.FILE
import func POSIX.fopen
import func libc.fclose
import func libc.ferror
import func libc.fgetc
import var libc.EOF

/**
 An instance of `File` represents a file with a defined path on
 the filesystem that may or may not exist.
*/
public struct File {
    let path: String

    public init(path: String...) {
        self.path = Path.join(path)
    }

    /**
     Returns a generator for the file contents separated by the 
     provided character.
     
     Character must be representable as a single 8 bit integer.
     
     Generator ends at EOF or on read error, we cannot report the
     read error, so to detect this query `ferror`.
     
     In the event of read-error we do not feed a partially generated
     line before ending iteration.
    */
    public func enumerate(separator: Character = "\n") throws -> FileLineGenerator {
        return try FileLineGenerator(path: path, separator: separator)
    }
}

/**
 - See: File.enumerate
*/
public class FileLineGenerator: IteratorProtocol, Sequence {
    private let fp: UnsafeMutablePointer<FILE>
    private let separator: Int32

    init(path: String, separator c: Character) throws {
        separator = Int32(String(c).utf8.first!)
        fp = try fopen(path)
    }

    deinit {
        if fp != nil {
            fclose(fp)
        }
    }

    public func next() -> String? {
        var out = ""
        while true {
            let c = fgetc(fp)
            if c == EOF {
                let err = ferror(fp)
                if err == 0 {
                    // if we have some string, return it, then next next() we will
                    // immediately EOF and stop generating
                    return out.isEmpty ? nil : out
                } else {
                    return nil
                }
            }
            if c == separator { return out }

            // fgetc is documented to return unsigned char converted to an int
            out.append(UnicodeScalar(UInt8(c)))
        }
    }
}
