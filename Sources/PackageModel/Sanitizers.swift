//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Available runtime sanitizers.
public enum Sanitizer: String, Encodable, CaseIterable {
    case address
    case thread
    case undefined
    case scudo

    /// Return an established short name for a sanitizer, e.g. "asan".
    public var shortName: String {
        switch self {
            case .address: return "asan"
            case .thread: return "tsan"
            case .undefined: return "ubsan"
            case .scudo: return "scudo"
        }
    }
}

/// A set of enabled runtime sanitizers.
public struct EnabledSanitizers: Encodable {
    /// A set of enabled sanitizers.
    public let sanitizers: Set<Sanitizer>

    public init(_ sanitizers: Set<Sanitizer> = []) {
        // FIXME: We need to throw from here if given sanitizers can't be
        // enabled.  For e.g., it is illegal to enable thread and address
        // sanitizers together.
        self.sanitizers = sanitizers
    }

    /// Sanitization flags for the C family compiler (C/C++).
    public func compileCFlags() -> [String] {
        return sanitizers.map({ "-fsanitize=\($0.rawValue)" })
    }

    /// Sanitization flags for the Swift compiler.
    public func compileSwiftFlags() -> [String] {
        return sanitizers.map({ "-sanitize=\($0.rawValue)" })
    }

    /// Sanitization flags for the Swift linker and compiler are the same so far.
    public func linkSwiftFlags() -> [String] {
        return compileSwiftFlags()
    }

    public var isEmpty: Bool {
        return sanitizers.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case sanitizers
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sanitizers.sorted{ $0.rawValue < $1.rawValue }, forKey: .sanitizers)
    }
}
