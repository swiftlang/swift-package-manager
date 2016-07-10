/*
 This source file is part of the Swift.org open source project
 
 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

extension Collection {
    
    public func pick(_ body: (Iterator.Element) -> Bool) -> Iterator.Element? {
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
    
    public func partition(_ body: (Iterator.Element) -> Bool) -> ([Iterator.Element], [Iterator.Element]) {
        var a: [Iterator.Element] = []
        var b: [Iterator.Element] = []
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

extension Collection where Iterator.Element : Equatable {
    
    /// Split around a delimiting subsequence with maximum number of splits == 2
    func split(around delimiter: [Iterator.Element]) -> ([Iterator.Element], [Iterator.Element]?) {
        
        let orig = Array(self)
        let end = orig.endIndex
        let delimCount = delimiter.count
        
        var index = orig.startIndex
        while index+delimCount <= end {
            let cur = Array(orig[index..<index+delimCount])
            if cur == delimiter {
                //found
                let leading = Array(orig[0..<index])
                let trailing = Array(orig.suffix(orig.count-leading.count-delimCount))
                return (leading, trailing)
            } else {
                //not found, move index down
                index += 1
            }
        }
        return (orig, nil)
    }
}

extension Collection where Iterator.Element: Hashable {

    /// Returns Unique elements from this collection maintaining its Order.
    public func unique() -> [Iterator.Element]{
        var registry = Set<Iterator.Element>()
        var elements = Array<Iterator.Element>()

        for item in self {
            guard !registry.contains(item) else { continue }

            registry.insert(item)
            elements.append(item)
        }

        return elements
    }
}
