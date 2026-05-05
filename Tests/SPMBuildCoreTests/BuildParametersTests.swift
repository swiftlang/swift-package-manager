//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@testable import SPMBuildCore
import Basics
import struct PackageModel.BuildEnvironment
import struct PackageModel.Platform
import _InternalTestSupport
import Testing

struct BuildParametersTests {
    @Test
    func configurationDependentProperties() throws {
        var parameters = mockBuildParameters(
            destination: .host,
            environment: BuildEnvironment(platform: .linux, configuration: .debug),
            buildSystem: .swiftbuild,
        )
        #expect(parameters.enableTestability)
        parameters.configuration = .release
        #expect(!parameters.enableTestability)
    }

    /// Covers the path that `llvm-cov export` must be given so that it can read the
    /// coverage mapping embedded in the compiled test code. For every build-system +
    /// platform combination this is the same file that gets launched to run the tests —
    /// *except* for SwiftBuild on non-Darwin, where the launched file is a thin
    /// `-test-runner` executable and the instrumented test code lives in a sibling
    /// shared library. Passing the runner to `llvm-cov` hides every user source file
    /// from the coverage report (see rdar://168006617).
    ///
    /// The Windows rows are a best-guess extrapolation (swiftbuild produces `<name>.dll`
    /// alongside `<name>-test-runner.exe`, mirroring the Linux `.so` pattern). The real
    /// behaviour hasn't been observed end-to-end yet; if it turns out to differ, update
    /// the expectations here and in `testCoverageBinaryRelativePath`.
    @Test(
        .tags(
            .TestSize.small,
        ),
        arguments: [
            // (build system, platform, test product name, expected relative path)
            (BuildSystemProvider.Kind.native, Platform.linux, "ReproTests", "ReproTests.xctest"),
            (BuildSystemProvider.Kind.native, Platform.macOS, "ReproTests", RelativePath("ReproTests.xctest/Contents/MacOS/ReproTests").pathString),
            (BuildSystemProvider.Kind.native, Platform.windows, "ReproTests", "ReproTests.xctest"),
            (BuildSystemProvider.Kind.swiftbuild, Platform.macOS, "ReproTests", RelativePath("ReproTests.xctest/Contents/MacOS/ReproTests").pathString),
            // The originally failing case: on non-Darwin swiftbuild, coverage mapping lives in
            // the shared library, not the `-test-runner` launcher.
            (BuildSystemProvider.Kind.swiftbuild, Platform.linux, "ReproTests", "ReproTests.so"),
            (BuildSystemProvider.Kind.swiftbuild, Platform.windows, "ReproTests", "ReproTests.dll"),
            // A differently-named product exercises that the name is not hard-coded anywhere.
            (BuildSystemProvider.Kind.swiftbuild, Platform.linux, "MyPkgTests", "MyPkgTests.so"),
        ],
    )
    func testCoverageBinaryRelativePath_returnsArtifactWithInstrumentedCoverage(
        buildSystem: BuildSystemProvider.Kind,
        platform: Platform,
        testProductName: String,
        expectedPath: String,
    ) throws {
        let parameters = mockBuildParameters(
            destination: .host,
            environment: BuildEnvironment(platform: platform, configuration: .debug),
            buildSystem: buildSystem,
        )

        let path = try parameters.testCoverageBinaryRelativePath(forTestProductName: testProductName)

        #expect(path.pathString == expectedPath)
    }
}
