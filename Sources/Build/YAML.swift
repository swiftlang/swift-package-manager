/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Path
import struct libc.FILE
import func libc.fclose
import POSIX

class YAML {
    let path: String
    private let fp: UnsafeMutablePointer<FILE>

    init(path: String...) throws {
        self.path = Path.join(path)
        fp = try fopen(self.path, mode: .Write)
    }

    func close() {
        fclose(fp)
    }

    func write(anys: Any...) throws {
        var anys = anys
        try fputs(anys.removeFirst() as! String, fp)
        if !anys.isEmpty {
            try fputs(anys.map(toYAML).joinWithSeparator(""), fp)
        }
        try fputs("\n", fp)

    }
}

private func toYAML(any: Any) -> String {

    func quote(input: String) -> String {
        for c in input.characters {
            if c == "@" || c == " " || c == "-" {
                return "\"\(input)\""
            }
        }
        return input
    }

    switch any {
    case let string as String where string == "":
        return "\"\""
    case let string as String:
        return string
    case let array as [String]:
        return "[" + array.map(quote).joinWithSeparator(", ") + "]"
    case let bool as Bool:
        return bool ? "true" : "false"
    default:
        fatalError("Unimplemented YAML type")
    }
}
