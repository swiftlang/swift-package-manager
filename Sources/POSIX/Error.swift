/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum SystemError: Swift.Error {
    case close(Int32)
    case pipe(Int32)
    case posix_spawn(Int32, [String])
    case read(Int32)
    case setenv(Int32, String)
    case unsetenv(Int32, String)
}

import func SPMLibc.strerror_r
import var SPMLibc.EINVAL
import var SPMLibc.ERANGE

extension SystemError: CustomStringConvertible {
    public var description: String {
        func strerror(_ errno: Int32) -> String {
            var cap = 64
            while cap <= 16 * 1024 {
                var buf = [Int8](repeating: 0, count: cap)
                let err = SPMLibc.strerror_r(errno, &buf, buf.count)
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
        case .close(let errno):
            return "close error: \(strerror(errno))"
        case .pipe(let errno):
            return "pipe error: \(strerror(errno))"
        case .posix_spawn(let errno, let args):
            return "posix_spawn error: \(strerror(errno)), `\(args)`"
        case .read(let errno):
            return "read error: \(strerror(errno))"
        case .setenv(let errno, let key):
            return "setenv error: \(strerror(errno)): \(key)"
        case .unsetenv(let errno, let key):
            return "unsetenv error: \(strerror(errno)): \(key)"
        }
    }
}
