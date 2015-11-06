/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)

public extension String {
    public func hasPrefix(str: String) -> Bool {
        if utf8.count < str.utf8.count {
            return false
        }
        for i in 0..<str.utf8.count {
            if utf8[utf8.startIndex.advancedBy(i)] != str.utf8[str.utf8.startIndex.advancedBy(i)] {
                return false
            }
        }
        return true
    }
    
    public func hasSuffix(str: String) -> Bool {
        let count = utf8.count
        let strCount = str.utf8.count
        if count < strCount {
            return false
        }
        for i in 0..<str.utf8.count {
            if utf8[utf8.startIndex.advancedBy(count-i-1)] != str.utf8[str.utf8.startIndex.advancedBy(strCount-i-1)] {
                return false
            }
        }
        return true
    }
}

#endif
