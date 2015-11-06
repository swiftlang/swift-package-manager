/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public enum Verbosity: Int {
    case Concise
    case Verbose
    case Debug

    public init(rawValue: Int) {
        switch rawValue {
        case Int.min...0:
            self = .Concise
        case 1:
            self = .Verbose
        default:
            self = .Debug
        }
    }
}

public var verbosity = Verbosity.Concise


import func libc.fputs
import var libc.stderr

public class StandardErrorOutputStream: OutputStreamType {
    public func write(string: String) {
        libc.fputs(string, libc.stderr)
    }
}

public var stderr = StandardErrorOutputStream()
