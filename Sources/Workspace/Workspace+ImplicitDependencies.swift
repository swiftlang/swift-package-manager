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
import PackageGraph
import PackageModel

extension Workspace {
    /// The implicit dependencies to introduce when using the standard library
    /// package.
    public static var standardLibraryPackageImplicitDependencies: ImplicitDependency {
        ImplicitDependency(
            package: standardLibraryPackageDependency,
            products: [ "Swift" ]
        )
    }

    fileprivate static var swiftRepositoryURL: SourceControlURL {
        "https://github.com/DougGregor/swift/"
    }

    fileprivate static var standardLibraryPackageBranch: String {
        "embedded-swift-stdlib-package"
    }

    /// Dependency on the standard library package.
    public static var standardLibraryPackageDependency: PackageDependency {
        .sourceControl(
            identity: .init(url: swiftRepositoryURL),
            nameForTargetDependencyResolutionOnly: nil,
            location: .remote(swiftRepositoryURL),
            requirement: .branch(standardLibraryPackageBranch),
            productFilter: .everything
        )
    }
}
