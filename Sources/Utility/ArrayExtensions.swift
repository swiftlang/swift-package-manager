/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension Array {
    public func pick(body: (Element) -> Bool) -> Element? {
        for x in self where body(x) {
            return x
        }
        return nil
    }

    public func partition<T, U>() -> ([T], [U]) {
        var t = [T]()
        var u = [U]()
        for e in self {
            if let e = e as? T {
                t.append(e)
            } else if let e = e as? U {
                u.append(e)
            }
        }
        return (t, u)
    }

    public func partition(body: (Element) -> Bool) -> ([Element], [Element]) {
        var a = [Element]()
        var b = [Element]()
        for e in self {
            if body(e) {
                a.append(e)
            } else {
                b.append(e)
            }
        }
        return (a, b)
    }
}
