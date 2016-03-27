/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import typealias libc.time_t
import func libc.strftime
import func libc.gmtime
import func libc.time

public enum StringError: ErrorProtocol {
    case NotEnoughSpace
}

extension StringError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .NotEnoughSpace:
            return "gmtime error: not enough space, increase resultSize."
        }
    }
}

public func gmtime(format: String, resultSize: Int = 200) throws -> String {
    var time = 0
    libc.time(&time)

    let result = UnsafeMutablePointer<Int8>(allocatingCapacity: resultSize)
    defer {
        result.deallocateCapacity(resultSize)
    }

    let gmTime = gmtime(&time)
    guard libc.strftime(result, resultSize, format, gmTime) != 0 else {
        throw StringError.NotEnoughSpace
    }

    return String(cString: result)
}
