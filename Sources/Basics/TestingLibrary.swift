//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// The testing libraries supported by the package manager.
public enum TestingLibrary: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// The XCTest library.
    ///
    /// This case represents both the open-source swift-corelibs-xctest
    /// package and Apple's XCTest framework that ships with Xcode.
    case xctest

    /// The swift-testing library.
    case swiftTesting

    /// A library specified by name _other than_ XCTest or Swift Testing.
    ///
    /// - Parameters:
    ///   - name: The name of the library. The formatting of this string is
    ///     unspecified.
    case other(_ name: String)

    public init(_ name: String) {
        switch name.filter(\.isLetter).lowercased() {
        case "xctest":
            self = .xctest
        case "swifttesting":
            self = .swiftTesting
        default:
            self = .other(name)
        }
    }

    public init(argument: String) {
        self.init(argument)
    }

    public var shortName: String {
        switch self {
        case .xctest:
            "xctest"
        case .swiftTesting:
            "swift-testing"
        case let .other(name):
            name
        }
    }

    public var description: String {
        switch self {
        case .xctest:
            "XCTest"
        case .swiftTesting:
            "Swift Testing"
        case let .other(name):
            name
        }
    }
}

