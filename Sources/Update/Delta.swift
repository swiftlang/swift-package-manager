/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct PackageDescription.Version

public struct Delta {
    public var added: [String] = []
    public var changed: [(String, old: Version, new: Version)] = []
    public var renamed: [(old: String, new: String)] = []
    public var unchanged: [(String, Version)] = []
}
