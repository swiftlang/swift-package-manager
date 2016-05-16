/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -------------------------------------------------------------------------
 Everything here should be moved to better places, it is a temporary
 repository for modules-to-be.
*/

import POSIX
import var libc.ENOENT
import Foundation


#if os(OSX) || os(iOS) || os(Linux)
    extension Character {
        public static var newline: Character { return "\n" }
    }
#else
    //ERROR: Unsupported platform
#endif


// Temporary extension until SwiftFoundation API is updated.
#if os(Linux)
    extension NSFileManager {
        static func `default`() -> NSFileManager {
            return defaultManager()
        }
    }
#endif
