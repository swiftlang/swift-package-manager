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
public enum TestingLibrary: Sendable, CustomStringConvertible {
  /// The XCTest library.
  ///
  /// This case represents both the open-source swift-corelibs-xctest
  /// package and Apple's XCTest framework that ships with Xcode.
  case xctest

  /// The swift-testing library.
  case swiftTesting

  public var description: String {
    switch self {
    case .xctest:
      "XCTest"
    case .swiftTesting:
      "Swift Testing"
    }
  }
}

