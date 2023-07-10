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

import Basics
import PackageModel

public protocol PackageGraphInfo {
    var products: [ProductInfo] { get }
    var targets: [TargetInfo] { get }
}

public protocol ProductInfo {
    var package: PackageInfo { get }
    var name: String { get }
    var type: ProductType { get }
    var targets: [TargetInfo] { get }
}

public protocol TargetInfo {
    var package: PackageInfo { get }
    var name: String { get }
    var type: Target.Kind { get }

    var isSwiftTarget: Bool { get }
    var c99name: String { get }
    var derivedSupportedPlatforms: [SupportedPlatform] { get }

    // note: this is only used by snippet targets and only accurate for them
    var sourcesDirectory: AbsolutePath? { get }
}

public protocol PackageInfo {
    var identity: String { get }
    var isRoot: Bool { get }
}
