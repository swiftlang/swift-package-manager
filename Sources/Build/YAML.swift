/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

protocol YAMLRepresentable {
    var YAML: String { get }
}

extension String: YAMLRepresentable {
    var YAML: String {
        if self == "" { return "\"\"" }
        for c in utf8 {
            switch c {
            case UInt8(ascii: "@"), UInt8(ascii: " "), UInt8(ascii: "-"), UInt8(ascii: "&"):
                return "\"\(self)\""
            default:
                continue
            }
        }
        return self
    }
}

extension Bool: YAMLRepresentable {
    var YAML: String {
        if self { return "true" }
        return "false"
    }
}

extension Array where Element: YAMLRepresentable {
    var YAML: String {
        return "[" + map{$0.YAML}.joined(separator: ", ") + "]"
    }
}
