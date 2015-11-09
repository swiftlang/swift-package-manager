/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import dep
import var libc.stdin
import POSIX
import sys

extension Process {
    /**
     A string representing the command that can be pasted into a shell.
    */
    static var prettyArguments: String {
        return Process.arguments.map { arg in
            let chars = arg.characters
            if chars.contains(" ") {
                return chars.split(" ").map(String.init).joinWithSeparator("\\ ")
            } else {
                return arg
            }
        }.joinWithSeparator(" ")
    }
}

@noreturn func die(msg: String) {
    print(msg, toStream: &stderr)
    exit(1)
}


//TODO move to functional kit of some kind
extension SequenceType {
    var isEmpty: Bool {
        for _ in self {
            return false
        }
        return true
    }
}

extension Array {
    func part(body: (Element) -> Bool) -> (Array, Array) {
        var a = Array()
        var b = Array()
        let f = Array.append
        for x in self {
            (body(x) ? f(&a) : f(&b))(x)
        }
        return (a, b)
    }
}
