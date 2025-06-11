/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

package struct ReferencedSymbols {
    package private(set) var defined: Set<String>
    package private(set) var undefined: Set<String>

    package init() {
        self.defined = []
        self.undefined = []
    }

    mutating func addUndefined(_ name: String) {
        guard !self.defined.contains(name) else {
            return
        }
        self.undefined.insert(name)
    }

    mutating func addDefined(_ name: String) {
        self.defined.insert(name)
        self.undefined.remove(name)
    }
}
