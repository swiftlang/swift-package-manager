//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2023-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if canImport(os)
import os

extension os.OSLog {
    @usableFromInline
    static let swiftpm = os.OSLog(subsystem: "org.swift.swiftpm", category: "default")
}
#endif

/// Emits a signpost.
@inlinable package func os_signpost(
    _ type: SignpostType,
    name: StaticString,
    signpostID: SignpostID = .exclusive
) {
    #if canImport(os) && DEBUG
    if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *) {
        os.os_signpost(
            type.underlying,
            log: .swiftpm,
            name: name,
            signpostID: signpostID.underlying
        )
    }
    #endif
}

@usableFromInline
package enum SignpostType {
    case begin
    case end
    case event

    #if canImport(os)
    @available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
    @usableFromInline
    var underlying: os.OSSignpostType {
        switch self {
        case .begin:
            return os.OSSignpostType.begin
        case .end:
            return os.OSSignpostType.end
        case .event:
            return os.OSSignpostType.event
        }
    }
    #endif
}

@usableFromInline
package enum SignpostID {
    case exclusive

    #if canImport(os)
    @available(macOS 10.14, iOS 12, tvOS 12, watchOS 5, *)
    @usableFromInline
    var underlying: os.OSSignpostID {
        switch self {
        case .exclusive:
            return os.OSSignpostID.exclusive
        }
    }
    #endif
}


package enum SignpostName {
    public static let updatingDependencies: StaticString = "updating"
    public static let resolvingDependencies: StaticString = "resolving"
    public static let pubgrub: StaticString = "pubgrub"
    public static let loadingGraph: StaticString = "loading graph"
}
