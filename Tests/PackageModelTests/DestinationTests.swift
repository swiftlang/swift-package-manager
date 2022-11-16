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
import TSCBasic
import TSCUtility
import XCTest

private let bundleRootPath = try! AbsolutePath(validating: "/tmp/cross-toolchain")
private let toolchainBinDir = RelativePath("swift.xctoolchain/usr/bin")
private let sdkRootDir = RelativePath("ubuntu-jammy.sdk")
private let hostTriple = "arm64-apple-darwin22.1.0"
private let targetTriple = "x86_64-unknown-linux-gnu"
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
        "target": "\#(targetTriple)",
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
        "targetTriples": ["\#(targetTriple)"],
        "extraCCFlags": \#(extraFlags.cCompilerFlags),
        "extraSwiftCFlags": \#(extraFlags.swiftCompilerFlags),
        "extraCXXFlags": \#(extraFlags.cxxCompilerFlags),
        "extraLinkerFlags": \#(extraFlags.linkerFlags)
    }
    """#

final class DestinationTests: XCTestCase {
    func testDestinationCodable() throws {
        let fs = InMemoryFileSystem(files: [
            "\(bundleRootPath)/destinationV1.json": ByteString(encodingAsUTF8: destinationV1JSON),
            "\(bundleRootPath)/destinationV2.json": ByteString(encodingAsUTF8: destinationV2JSON),
        ])

        let destinationV1 = try Destination(fromFile: bundleRootPath.appending(.init("destinationV1.json")), fileSystem: fs)

        var flagsWithoutLinkerFlags = extraFlags
        flagsWithoutLinkerFlags.linkerFlags = []

        let sdkRootAbsolutePath = bundleRootPath.appending(sdkRootDir)
        let toolchainBinAbsolutePath = bundleRootPath.appending(toolchainBinDir)

        XCTAssertEqual(
            destinationV1,
            Destination(
                targetTriple: try Triple(targetTriple),
                sdkRootDir: sdkRootAbsolutePath,
                toolchainBinDir: toolchainBinAbsolutePath,
                extraFlags: flagsWithoutLinkerFlags
            )
        )

        let destinationV2 = try Destination(fromFile: bundleRootPath.appending(.init("destinationV2.json")), fileSystem: fs)

        XCTAssertEqual(
            destinationV2,
            Destination(
                hostTriple: try Triple(hostTriple),
                targetTriple: try Triple(targetTriple),
                sdkRootDir: sdkRootAbsolutePath,
                toolchainBinDir: toolchainBinAbsolutePath,
                extraFlags: extraFlags
            )
        )
    }
}
