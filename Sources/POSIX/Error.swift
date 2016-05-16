/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum SystemError: ErrorProtocol {
    case chdir(Int32)
    case close(Int32)
    case pipe(Int32)
    case popen(Int32, String)
    case posix_spawn(Int32, [String])
    case read(Int32)
    case realpath(Int32, String)
    case waitpid(Int32)
}

import func libc.strerror


extension SystemError: CustomStringConvertible {
    public var description: String {

        func strerror(_ errno: Int32) -> String {
            let cmsg = libc.strerror(errno)!
            let msg = String(validatingUTF8: cmsg) ?? "Unknown Error"
            return "\(msg) (\(errno))"
        }

        switch self {
        case .chdir(let errno):
            return "chdir error: \(strerror(errno))"
        case .close(let errno):
            return "close error: \(strerror(errno))"
        case .pipe(let errno):
            return "pipe error: \(strerror(errno))"
        case .posix_spawn(let errno, let args):
            return "posix_spawn error: \(strerror(errno)), `\(args)`"
        case .popen(let errno, _):
            return "popen error: \(strerror(errno))"
        case .read(let errno):
            return "read error: \(strerror(errno))"
        case .realpath(let errno, let path):
            return "realpath error: \(strerror(errno)): \(path)"
        case .waitpid(let errno):
            return "waitpid error: \(strerror(errno))"
        }
    }
}


public enum Error: ErrorProtocol {
    case ExitStatus(Int32, [String])
    case ExitSignal
}

public enum ShellError: ErrorProtocol {
    case system(arguments: [String], SystemError)
    case popen(arguments: [String], SystemError)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .ExitStatus(let code, let args):
            return "exit(\(code)): \(prettyArguments(args))"

        case .ExitSignal:
            return "Child process exited with signal"
        }
    }
}
