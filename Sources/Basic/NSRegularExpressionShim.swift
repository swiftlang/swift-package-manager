/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

#if os(macOS)
// Compatibility shim.
// <rdar://problem/30488747> NSTextCheckingResult doesn't have range(at:) method
extension NSTextCheckingResult {
    public func range(at idx: Int) -> NSRange {
        return rangeAt(idx)
    }
}
#endif
