//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics

public struct BuildCacheConfiguration: Equatable, Sendable, Encodable {
    public enum SizeLimit: Equatable, Sendable, Encodable {
        case size(String)

        case percent(Int)

        public static func make(size: String?, percent: Int?) throws -> Self? {
            if size != nil, percent != nil {
                throw InvalidSizeLimitError.conflictingSizeAndPercentage
            }
            if let percent {
                return .percent(percent)
            }
            if let size {
                return .size(size)
            }
            return nil
        }

        public static func parse(_ string: String) throws -> Self {
            if string.hasSuffix("%") {
                let digits = String(string.dropLast())
                guard let percent = Int(digits), (0...100).contains(percent) else {
                    throw InvalidSizeLimitError.invalidPercentage(string)
                }
                return .percent(percent)
            }
            return .size(string)
        }
    }

    public var enabled: Bool?

    public var casPath: Basics.AbsolutePath?

    public var sizeLimit: SizeLimit?

    public var enableDiagnosticRemarks: Bool?

    public var remoteServicePath: Basics.AbsolutePath?

    public var pluginPath: Basics.AbsolutePath?

    public var enablePrefixMapping: Bool?

    public init(
        enabled: Bool? = nil,
        casPath: Basics.AbsolutePath? = nil,
        sizeLimit: SizeLimit? = nil,
        enableDiagnosticRemarks: Bool? = nil,
        remoteServicePath: Basics.AbsolutePath? = nil,
        pluginPath: Basics.AbsolutePath? = nil,
        enablePrefixMapping: Bool? = nil
    ) {
        self.enabled = enabled
        self.casPath = casPath
        self.sizeLimit = sizeLimit
        self.enableDiagnosticRemarks = enableDiagnosticRemarks
        self.remoteServicePath = remoteServicePath
        self.pluginPath = pluginPath
        self.enablePrefixMapping = enablePrefixMapping
    }

    /// An empty configuration where nothing is set.
    public static var none: Self { .init() }

    public var isEmpty: Bool {
        self.enabled == nil
            && self.casPath == nil
            && self.sizeLimit == nil
            && self.enableDiagnosticRemarks == nil
            && self.remoteServicePath == nil
            && self.pluginPath == nil
            && self.enablePrefixMapping == nil
    }

    /// Returns a new configuration where the values in `self` take precedence
    /// over the corresponding values in `lower`, merged field-by-field.
    public func merging(over lower: BuildCacheConfiguration) -> BuildCacheConfiguration {
        .init(
            enabled: self.enabled ?? lower.enabled,
            casPath: self.casPath ?? lower.casPath,
            sizeLimit: self.sizeLimit ?? lower.sizeLimit,
            enableDiagnosticRemarks: self.enableDiagnosticRemarks ?? lower.enableDiagnosticRemarks,
            remoteServicePath: self.remoteServicePath ?? lower.remoteServicePath,
            pluginPath: self.pluginPath ?? lower.pluginPath,
            enablePrefixMapping: self.enablePrefixMapping ?? lower.enablePrefixMapping
        )
    }
}

/// An error thrown when a build cache size limit string cannot be parsed.
public enum InvalidSizeLimitError: Error, CustomStringConvertible {
    case invalidPercentage(String)
    case conflictingSizeAndPercentage

    public var description: String {
        switch self {
        case .invalidPercentage(let string):
            return "invalid size limit percentage '\(string)'; expected an integer between 0 and 100 followed by '%'"
        case .conflictingSizeAndPercentage:
            return "cannot specify both a size and a percentage for the build cache size limit"
        }
    }
}

