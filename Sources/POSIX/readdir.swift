/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import libc

extension dirent {
#if !os(OSX)
    // Add a portability wrapper.
    //
    // FIXME: This should come from the standard library: https://bugs.swift.org/browse/SR-1726
    public var d_namlen: UInt16 {
        get {
            return d_reclen
        }
        set {
            d_reclen = newValue
        }
    }
#endif

    /// Get the directory name.
    ///
    /// This returns nil if the name is not valid UTF8.
    public var name: String? {
        var name = self.d_name
        return withUnsafePointer(&name) { (ptr) -> String? in
            // FIXME: This is wasteful, but String doesn't have a public API
            // that let's us avoid the copy.
            var nameBytes = [CChar](UnsafeBufferPointer(start: unsafeBitCast(ptr, to: UnsafePointer<CChar>.self), count: Int(self.d_namlen)))
            nameBytes.append(0)
            return String(validatingUTF8: nameBytes)
        }
    }
}

// Re-export the typealias, for portability.
public typealias dirent = libc.dirent
