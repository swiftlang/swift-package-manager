/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public struct URL {
    public static func scheme(url: String) -> String? {
        // this is not fully RFC compliant, so it either has to be
        // or we need to use CFLite FIXME

        let count = url.characters.count

        func foo(start: Int) -> String? {
            guard count > start + 3 else { return nil }

            let a = url.startIndex
            let b = a.advanced(by: start)
            let c = b.advanced(by: 3)
            if url[b..<c] == "://" || url[b] == "@" {
                return url[a..<b]
            } else {
                return nil
            }
        }
        return foo(4) ?? foo(5) ?? foo(3)
    }
}
