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
        func quote(input: String) -> String {
            for c in input.characters {
                if c == "@" || c == " " || c == "-" {
                    return "\"\(input)\""
                }
            }
            return input
        }
        let stringArray = self.flatMap { String($0) }
        return "[" + stringArray.map(quote).joined(separator: ", ") + "]"
    }
}
