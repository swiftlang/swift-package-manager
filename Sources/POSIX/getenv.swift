/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import func libc.getenv

public func getenv(_ key: String) -> String? {
    let out = libc.getenv(key)
    return out == nil ? nil : String(validatingUTF8: out!)  //FIXME locale may not be UTF8
}
