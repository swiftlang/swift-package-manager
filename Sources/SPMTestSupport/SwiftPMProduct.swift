//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic

@_exported import TSCTestSupport

public enum SwiftPMProduct: Product {
    case SwiftBuild
    case SwiftPackage
    case SwiftPackageRegistry
    case SwiftTest
    case SwiftRun
    case XCTestHelper

    /// Executable name.
    public var exec: RelativePath {
        switch self {
        case .SwiftBuild:
            return RelativePath("swift-build")
        case .SwiftPackage:
            return RelativePath("swift-package")
        case .SwiftPackageRegistry:
            return RelativePath("swift-package-registry")
        case .SwiftTest:
            return RelativePath("swift-test")
        case .SwiftRun:
            return RelativePath("swift-run")
        case .XCTestHelper:
            return RelativePath("swiftpm-xctest-helper")
        }
    }
}
