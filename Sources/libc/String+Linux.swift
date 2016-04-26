/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 
 -----------------------------------------------------------------
*/

#if os(Linux)
    public extension String {
        public func hasPrefix(_ str: String) -> Bool {
            // FIXME: the cost of this "fast path" is O(n).
            if utf8.count < str.utf8.count {
                return false
            }
            // FIXME: the complexity of this algorithm is O(n^2).
            for i in 0..<str.utf8.count {
                if utf8[utf8.location(utf8.startIndex, offsetBy: i)] != str.utf8[str.utf8.location(str.utf8.startIndex, offsetBy: i)] {
                    return false
                }
            }
            return true
        }

        public func hasSuffix(_ str: String) -> Bool {
            let count = utf8.count
            let strCount = str.utf8.count
            if count < strCount {
                return false
            }
            // FIXME: the complexity of this algorithm is O(n^2).
            for i in 0..<strCount {
                if utf8[utf8.location(utf8.startIndex, offsetBy: count-i-1)] != str.utf8[str.utf8.location(str.utf8.startIndex, offsetBy: strCount-i-1)] {
                    return false
                }
            }
            return true
        }
    }
#endif
