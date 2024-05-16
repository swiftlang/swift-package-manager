//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import PackageGraph
import PackageModel

extension ResolvedTarget {
    public static func mock(
        packageIdentity: PackageIdentity,
        name: String,
        deps: ResolvedTarget...,
        conditions: [PackageCondition] = []
    ) -> ResolvedTarget {
        ResolvedTarget(
            packageIdentity: packageIdentity,
            underlying: SwiftTarget(
                name: name,
                type: .library,
                path: .root,
                sources: Sources(paths: [], root: "/"),
                dependencies: [],
                packageAccess: false,
                usesUnsafeFlags: false
            ),
            dependencies: deps.map { .target($0, conditions: conditions) },
            defaultLocalization: nil,
            supportedPlatforms: [],
            platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)
        )
    }
}

