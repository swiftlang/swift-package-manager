/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public protocol FixableError: CustomStringConvertible {
    var error: String { get }
    var fix: String? { get }
}

extension FixableError {
    public var description: String {
        switch fix {
        case let fix?: return "\(error) fix: \(fix)"
        case .none: return error
        }
    }
}
