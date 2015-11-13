/*
 This source file is part of the Swift.org open source project

 Copyright 2015 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/**
 For an array of String arguments that would be passed to system() or
 popen(), returns a pretty-printed string that is user-readable and
 could be typed into a Terminal to reattempt execution.
*/
public func prettyArguments(args: [String]) -> String {
    return args.map { arg in
        let chars = arg.characters
        if chars.contains(" ") {
            return chars.split(" ").map(String.init).joinWithSeparator("\\ ")
        } else {
            return arg
        }
    }.joinWithSeparator(" ")
}
