/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

// Can't conform a protocol explicitly with certain where clause for now but it'd be resolved by SE-0143.
// ref: https://github.com/apple/swift-evolution/blob/master/proposals/0143-conditional-conformances.md
// MARK: CustomStringConvertible
extension DictionaryLiteral where Key: CustomStringConvertible, Value: CustomStringConvertible {
    /// A string that represents the contents of the dictionary literal.
    public var description: String {
        let lastCount = self.count - 1
        var desc = "["
        for (i, item) in self.enumerated() {
            desc.append("\(item.key.description): \(item.value.description)")
            desc.append(i == lastCount ? "]" : ", ")
        }
        return desc
    }
}

// MARK: Equatable
extension DictionaryLiteral where Key: Equatable, Value: Equatable {
    public static func ==(lhs: DictionaryLiteral, rhs: DictionaryLiteral) -> Bool {
        if lhs.count != rhs.count {
            return false
        }
        for i in 0..<lhs.count {
            if lhs[i].key != rhs[i].key || lhs[i].value != rhs[i].value {
                return false
            }
        }
        return true
    }
}
