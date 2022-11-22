//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
@testable import PackageModel
@testable import SPMBuildCore
import TSCBasic
import TSCUtility
import XCTest

private let bundleRootPath = try! AbsolutePath(validating: "/tmp/cross-toolchain")
private let toolchainBinDir = RelativePath("swift.xctoolchain/usr/bin")
private let sdkRootDir = RelativePath("ubuntu-jammy.sdk")
private let hostTriple = try! Triple("arm64-apple-darwin22.1.0")
private let linuxGNUTargetTriple = try! Triple("x86_64-unknown-linux-gnu")
private let linuxMuslTargetTriple = try! Triple("x86_64-unknown-linux-musl")
private let extraFlags = BuildFlags(
    cCompilerFlags: ["-fintegrated-as"],
    cxxCompilerFlags: ["-fno-exceptions"],
    swiftCompilerFlags: ["-enable-experimental-cxx-interop", "-use-ld=lld"],
    linkerFlags: ["-R/usr/lib/swift/linux/"]
)

private let destinationV1JSON =
    #"""
    {
        "version": 1,
        "sdk": "\#(bundleRootPath.appending(sdkRootDir))",
        "toolchain-bin-dir": "\#(bundleRootPath.appending(toolchainBinDir))",
        "target": "\#(linuxGNUTargetTriple)",
        "extra-cc-flags": \#(extraFlags.cCompilerFlags),
        "extra-swiftc-flags": \#(extraFlags.swiftCompilerFlags),
        "extra-cpp-flags": \#(extraFlags.cxxCompilerFlags)
    }
    """#

private let destinationV2JSON =
    #"""
    {
        "version": 2,
        "sdkRootDir": "\#(sdkRootDir)",
        "toolchainBinDir": "\#(toolchainBinDir)",
        "hostTriples": ["\#(hostTriple)"],
        "targetTriples": ["\#(linuxGNUTargetTriple)"],
        "extraCCFlags": \#(extraFlags.cCompilerFlags),
        "extraSwiftCFlags": \#(extraFlags.swiftCompilerFlags),
        "extraCXXFlags": \#(extraFlags.cxxCompilerFlags),
        "extraLinkerFlags": \#(extraFlags.linkerFlags)
    }
    """#

private let sdkRootAbsolutePath = bundleRootPath.appending(sdkRootDir)
private let toolchainBinAbsolutePath = bundleRootPath.appending(toolchainBinDir)

private let parsedDestinationV2GNU = Destination(
    hostTriple: hostTriple,
    targetTriple: linuxGNUTargetTriple,
    sdkRootDir: sdkRootAbsolutePath,
    toolchainBinDir: toolchainBinAbsolutePath,
    extraFlags: extraFlags
)

private let parsedDestinationV2Musl = Destination(
    hostTriple: hostTriple,
    targetTriple: linuxMuslTargetTriple,
    sdkRootDir: sdkRootAbsolutePath,
    toolchainBinDir: toolchainBinAbsolutePath,
    extraFlags: extraFlags
)

final class DestinationTests: XCTestCase {
    func testDestinationCodable() throws {
        let fs = InMemoryFileSystem(files: [
            "\(bundleRootPath)/destinationV1.json": ByteString(encodingAsUTF8: destinationV1JSON),
            "\(bundleRootPath)/destinationV2.json": ByteString(encodingAsUTF8: destinationV2JSON),
        ])

        let destinationV1 = try Destination(fromFile: bundleRootPath.appending(.init("destinationV1.json")), fileSystem: fs)

        var flagsWithoutLinkerFlags = extraFlags
        flagsWithoutLinkerFlags.linkerFlags = []

        XCTAssertEqual(
            destinationV1,
            Destination(
                targetTriple: linuxGNUTargetTriple,
                sdkRootDir: sdkRootAbsolutePath,
                toolchainBinDir: toolchainBinAbsolutePath,
                extraFlags: flagsWithoutLinkerFlags
            )
        )

        let destinationV2 = try Destination(fromFile: bundleRootPath.appending(.init("destinationV2.json")), fileSystem: fs)

        XCTAssertEqual(destinationV2, parsedDestinationV2GNU)
    }

    func testSelectDestination() throws {
        let bundles = [
            DestinationsBundle(
                path: try AbsolutePath(validating: "/destination.artifactsbundle"),
                artifacts: [
                    "id1": [
                        .init(
                            metadata: .init(
                                path: "id1",
                                supportedTriples: [hostTriple]
                            ),
                            destination: parsedDestinationV2GNU
                        )
                    ],
                    "id2": [
                        .init(
                            metadata: .init(
                                path: "id2",
                                supportedTriples: []
                            ),
                            destination: parsedDestinationV2GNU
                        )
                    ],
                    "id3": [
                        .init(
                            metadata: .init(
                                path: "id3",
                                supportedTriples: [hostTriple]
                            ),
                            destination: parsedDestinationV2Musl
                        )
                    ]
                ]
            )
        ]

        let system = ObservabilitySystem.makeForTesting()

        XCTAssertEqual(
            bundles.selectDestination(
                matching: "id1",
                hostTriple: hostTriple,
                observabilityScope: system.topScope
            ),
            parsedDestinationV2GNU
        )

        // Expecting `nil` because no host triple is specified for this destination
        // in the fake destination bundle.
        XCTAssertNil(
            bundles.selectDestination(
                matching: "id2",
                hostTriple: hostTriple,
                observabilityScope: system.topScope
            )
        )

        XCTAssertEqual(
            bundles.selectDestination(
                matching: "id3",
                hostTriple: hostTriple,
                observabilityScope: system.topScope
            ),
            parsedDestinationV2Musl
        )
    }
}
