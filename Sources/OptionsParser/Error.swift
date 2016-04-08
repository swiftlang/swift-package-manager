/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

public enum Error: ErrorProtocol {
    case UnknownArgument(String)
    case MultipleModesSpecified([String])
    case ExpectedAssociatedValue(String)
    case UnexpectedAssociatedValue(String, String)
    case InvalidUsage(String)
}

extension Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case ExpectedAssociatedValue(let arg):
            return "expected associated value for argument: \(arg)"
        case UnexpectedAssociatedValue(let arg, let value):
            return "unexpected associated value for argument: \(arg)=\(value)"
        case .MultipleModesSpecified(let modes):
            return "multiple modes specified: \(modes)"
        case .UnknownArgument(let cmd):
            return "unknown command: \(cmd)"
        case .InvalidUsage(let hint):
            return "invalid usage: \(hint)"
        }
    }
}
