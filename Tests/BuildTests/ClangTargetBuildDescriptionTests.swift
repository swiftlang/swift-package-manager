//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import Build
import PackageGraph
import PackageModel
import SPMTestSupport
import XCTest

final class ClangTargetBuildDescriptionTests: XCTestCase {
    func testClangIndexStorePath() throws {
        let targetDescription = try makeTargetBuildDescription()
        XCTAssertTrue(try targetDescription.basicArguments().contains("-index-store-path"))
    }

    private func makeClangTarget() throws -> ClangTarget {
        try ClangTarget(
            name: "dummy",
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            includeDir: .root,
            moduleMapType: .none,
            type: .library,
            path: .root,
            sources: .init(paths: [.root.appending(component: "foo.c")], root: .root),
            usesUnsafeFlags: false
        )
    }

    private func makeResolvedTarget() throws -> ResolvedTarget {
        ResolvedTarget(
            packageIdentity: .plain("dummy"),
            underlying: try makeClangTarget(),
            dependencies: [],
            supportedPlatforms: [],
            platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)
        )
    }

    private func makeTargetBuildDescription() throws -> ClangTargetBuildDescription {
        let observability = ObservabilitySystem.makeForTesting(verbose: false)
        return try ClangTargetBuildDescription(
            target: try makeResolvedTarget(),
            toolsVersion: .current,
            buildParameters: mockBuildParameters(
                toolchain: try UserToolchain.default,
                indexStoreMode: .on
            ),
            fileSystem: localFileSystem,
            observabilityScope: observability.topScope
        )
    }
}
