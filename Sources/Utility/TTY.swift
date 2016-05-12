/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import func POSIX.isatty
import libc

/// Check if this stream is TTY.
public func isTTY(_ stream: Stream) -> Bool {
    switch stream {
    case .StdOut: return isatty(fileno(libc.stdout))
    case .StdErr: return isatty(fileno(libc.stderr))
    }
}

public enum Stream {
    case StdOut, StdErr
}
