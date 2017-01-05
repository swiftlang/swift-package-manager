/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basic

/// Useful extensions to JSON to use in assert methods where 
/// the type diagnostics is not that important.
public extension JSON {
    var dictionary: [String: JSON]? {
        if case let .dictionary(contents) = self {
            return contents
        }
        return nil
    }

    var array: [JSON]? {
        if case let .array(contents) = self {
            return contents
        }
        return nil
    }

    var string: String? {
        if case let .string(contents) = self {
            return contents
        }
        return nil
    }

    var stringValue: String {
        return string ?? ""
    }

    subscript(_ string: String) -> JSON? {
        return dictionary?[string]
    }

    subscript(_ idx: Int) -> JSON? {
        if let array = array {
            guard idx >= 0 && array.count > idx else {
                return nil
            }
            return array[idx]
        }
        return nil
    }
}
