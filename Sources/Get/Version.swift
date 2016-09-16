/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import struct Utility.Version

extension Version {
    static var max: Version {
        return Version(Int.max, Int.max, Int.max)
    }

    static var min: Version {
        return Version(0, 0, 0)
    }

    static var maxRange: Range<Version> {
        return self.min..<self.max
    }
}
