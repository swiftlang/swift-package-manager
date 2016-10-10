/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum SystemError: Swift.Error {
    case chdir(Int32, String)
    case close(Int32)
    case dirfd(Int32, String)
    case fgetc(Int32)
    case fread(Int32)
    case getcwd(Int32)
    case mkdir(Int32, String)
    case mkdtemp(Int32)
    case pipe(Int32)
    case popen(Int32, String)
    case posix_spawn(Int32, [String])
    case read(Int32)
    case readdir(Int32, String)
    case realpath(Int32, String)
    case rename(Int32, old: String, new: String)
    case rmdir(Int32, String)
    case stat(Int32, String)
    case symlink(Int32, String, dest: String)
    case symlinkat(Int32, String)
    case unlink(Int32, String)
    case waitpid(Int32)
}

import func libc.strerror_r
import var libc.EINVAL
import var libc.ERANGE


extension SystemError: CustomStringConvertible {
    public var description: String {
        func strerror(_ errno: Int32) -> String {
            var cap = 64
            while cap <= 16 * 1024 {
                var buf = [Int8](repeating: 0, count: cap)
                let err = libc.strerror_r(errno, &buf, buf.count)
                if err == EINVAL {
                    return "Unknown error \(errno)"
                }
                if err == ERANGE {
                    cap *= 2
                    continue
                }
                if err != 0 {
                    fatalError("strerror_r error: \(err)")
                }
                return "\(String(cString: buf)) (\(errno))"
            }
            fatalError("strerror_r error: \(ERANGE)")
        }
        
        switch self {
        case .chdir(let errno, let path):
            return "chdir error: \(strerror(errno)): \(path)"
        case .close(let errno):
            return "close error: \(strerror(errno))"
        case .dirfd(let errno, _):
            return "dirfd error: \(strerror(errno))"
        case .fgetc(let errno):
            return "fgetc error: \(strerror(errno))"
        case .fread(let errno):
            return "fread error: \(strerror(errno))"
        case .getcwd(let errno):
            return "getcwd error: \(strerror(errno))"
        case .mkdir(let errno, let path):
            return "mkdir error: \(strerror(errno)): \(path)"
        case .mkdtemp(let errno):
            return "mkdtemp error: \(strerror(errno))"
        case .pipe(let errno):
            return "pipe error: \(strerror(errno))"
        case .posix_spawn(let errno, let args):
            return "posix_spawn error: \(strerror(errno)), `\(args)`"
        case .popen(let errno, _):
            return "popen error: \(strerror(errno))"
        case .read(let errno):
            return "read error: \(strerror(errno))"
        case .readdir(let errno, _):
            return "readdir error: \(strerror(errno))"
        case .realpath(let errno, let path):
            return "realpath error: \(strerror(errno)): \(path)"
        case .rename(let errno, let old, let new):
            return "rename error: \(strerror(errno)): \(old) -> \(new)"
        case .rmdir(let errno, let path):
            return "rmdir error: \(strerror(errno)): \(path)"
        case .stat(let errno, _):
            return "stat error: \(strerror(errno))"
        case .symlink(let errno, let path, let dest):
            return "symlink error: \(strerror(errno)): \(path) -> \(dest)"
        case .symlinkat(let errno, _):
            return "symlinkat error: \(strerror(errno))"
        case .unlink(let errno, let path):
            return "unlink error: \(strerror(errno)): \(path)"
        case .waitpid(let errno):
            return "waitpid error: \(strerror(errno))"
        }
    }
}


public enum Error: Swift.Error {
    case exitStatus(Int32, [String])
    case exitSignal
}

public enum ShellError: Swift.Error {
    case system(arguments: [String], SystemError)
    case popen(arguments: [String], SystemError)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exitStatus(let code, let args):
            return "exit(\(code)): \(prettyArguments(args))"

        case .exitSignal:
            return "Child process exited with signal"
        }
    }
}
