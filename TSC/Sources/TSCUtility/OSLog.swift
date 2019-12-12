/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic

extension OSLog {
    /// Log for SwiftPM.
    public static let swiftpm = OSLog(subsystem: "org.swift.swiftpm", category: "default")
}

public enum SignpostName {
    /// SignPost name for package resolution.
    public static let resolution: StaticString = "resolution"
}
