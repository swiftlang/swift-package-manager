/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

public protocol Argument {
    /**
     Attempt to convert the provided argument. If you need
     an associated value, call `pop()`, if there is no
     associated value we will throw. If the argument was
     passed `--foo=bar` and you don’t `pop` we also `throw`
    */
    init?(argument: String, pop: () -> String?) throws
}
