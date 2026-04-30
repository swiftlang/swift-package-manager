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
import enum PackageModel.BuildConfiguration
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

    @Test(arguments: [
        (triple: "wasm32-unknown-wasi", suffix: "-wasi"),
        (triple: "wasm32-unknown-wasip1", suffix: "-wasi"),
        (triple: "wasm32-unknown-wasip1-threads", suffix: "-wasi"),
        (triple: "wasm32-unknown-wasip2", suffix: "-wasi"),
        (triple: "wasm64-unknown-wasi", suffix: "-wasi"),
        (triple: "wasm32-unknown-emscripten", suffix: "-emscripten"),
        (triple: "wasm32-unknown-none-wasm", suffix: "-webassembly"),
    ] as [(triple: String, suffix: String)],
    [
        (config: BuildConfiguration.debug, buildSystem: BuildSystemProvider.Kind.swiftbuild),
        (config: .debug, buildSystem: .xcode),
        (config: .release, buildSystem: .swiftbuild),
        (config: .release, buildSystem: .xcode),
    ] as [(config: BuildConfiguration, buildSystem: BuildSystemProvider.Kind)])
    func productsDirSuffixIsDerivedFromTriple(
        tripleAndSuffix: (triple: String, suffix: String),
        configAndBuildSystem: (config: BuildConfiguration, buildSystem: BuildSystemProvider.Kind),
    ) throws {
        // The expected-suffix column must stay byte-exact with swift-build's
        // `WebAssemblyPlatformExtension.platformName(triple:)` (wasi, emscripten)
        // and with swift-build's pre-#1335 legacy "webassembly" platform name
        // (bare-metal wasm). A mismatch breaks `swift build --show-bin-path` /
        // `swift run` path resolution under `.swiftbuild` — the exact regression
        // that caused PR #1335 to be reverted.
        let parsedTriple = try Basics.Triple(tripleAndSuffix.triple)
        let parameters = mockBuildParameters(
            destination: .target,
            config: configAndBuildSystem.config,
            buildSystemKind: configAndBuildSystem.buildSystem,
            triple: parsedTriple,
        )
        let configDir = parameters.buildPath.basename
        let expectedConfigPrefix = configAndBuildSystem.config.dirname.capitalized
        #expect(
            configDir == expectedConfigPrefix + tripleAndSuffix.suffix,
            """
            triple \(tripleAndSuffix.triple) / config \(configAndBuildSystem.config) / \
            buildSystem \(configAndBuildSystem.buildSystem) must yield \
            Products/\(expectedConfigPrefix)\(tripleAndSuffix.suffix) \
            (got \"\(configDir)\")
            """,
        )
    }
}
