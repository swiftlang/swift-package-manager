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
private let toolchainBinDir = bundleRootPath.appending(.init("swift.xctoolchain/usr/bin"))
private let sdkRootDir = bundleRootPath.appending(.init("ubuntu-jammy.sdk"))
private let destinationTriple = "x86_64-unknown-linux-gnu"
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
        "sdk": "\#(sdkRootDir)",
        "toolchain-bin-dir": "\#(toolchainBinDir)",
        "target": "\#(destinationTriple)",
        "extra-cc-flags": \#(extraFlags.cCompilerFlags),
        "extra-swiftc-flags": \#(extraFlags.swiftCompilerFlags),
        "extra-cpp-flags": \#(extraFlags.cxxCompilerFlags)
    }
    """#

class DestinationTests: XCTestCase {
    func testDestinationCodable() throws {
        let fs = InMemoryFileSystem(files: ["/sdk/destination.json": ByteString(encodingAsUTF8: destinationV1JSON)])

        let destinationV1 = try Destination(fromFile: AbsolutePath(validating: "/sdk/destination.json"), fileSystem: fs)

        var flagsWithoutLinkerFlags = extraFlags
        flagsWithoutLinkerFlags.linkerFlags = []

        XCTAssertEqual(
            destinationV1,
            Destination(
                destinationTriple: try Triple(destinationTriple),
                sdkRootDir: sdkRootDir,
                toolchainBinDir: toolchainBinDir,
                extraFlags: flagsWithoutLinkerFlags
            )
        )
    }
}
