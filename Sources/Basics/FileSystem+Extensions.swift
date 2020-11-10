/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import TSCBasic

extension FileSystem {
    /// SwiftPM directory under user's home directory (~/.swiftpm)
    public var dotSwiftPM: AbsolutePath {
        return self.homeDirectory.appending(component: ".swiftpm")
    }
}

extension FileSystem {
    /// SwiftPM cache directory under user's caches directory (if exists)
    public var swiftPMCacheDirectory: AbsolutePath {
        if let cachesDirectory = self.cachesDirectory {
            return cachesDirectory.appending(component: "org.swift.swiftpm")
        } else {
            return self.dotSwiftPM.appending(component: "cache")
        }
    }
}
