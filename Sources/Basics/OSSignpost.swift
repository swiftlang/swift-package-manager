//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(os)
import os
#endif

/// Emits a signpost.
@inlinable public func os_signpost(
    _ type: os.OSSignpostType,
    name: StaticString,
    log: os.OSLog = .swiftpm,
    signpostID: os.OSSignpostID = .exclusive
) {
    #if DEBUG && canImport(os)
    if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
        os.os_signpost(type, log: log, name: name, signpostID: signpostID)
    }
    #endif
}


extension os.OSLog {
    public static let swiftpm = os.OSLog(subsystem: "org.swift.swiftpm", category: "default")
}

public enum SignpostName {
    public static let updatingDependencies: StaticString = "updating"
    public static let resolvingDependencies: StaticString = "resolving"
    public static let pubgrub: StaticString = "pubgrub"
    public static let loadingGraph: StaticString = "loading graph"
}
