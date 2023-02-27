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

private let destinationV1 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/destinationV1.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "version": 1,
        "sdk": "\#(bundleRootPath.appending(sdkRootDir))",
        "toolchain-bin-dir": "\#(bundleRootPath.appending(toolchainBinDir))",
        "target": "\#(linuxGNUTargetTriple.tripleString)",
        "extra-cc-flags": \#(extraFlags.cCompilerFlags),
        "extra-swiftc-flags": \#(extraFlags.swiftCompilerFlags),
        "extra-cpp-flags": \#(extraFlags.cxxCompilerFlags)
    }
    """#)
)

private let destinationV2 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/destinationV2.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "version": 2,
        "sdkRootDir": "\#(sdkRootDir)",
        "toolchainBinDir": "\#(toolchainBinDir)",
        "hostTriples": ["\#(hostTriple.tripleString)"],
        "targetTriples": ["\#(linuxGNUTargetTriple.tripleString)"],
        "extraCCFlags": \#(extraFlags.cCompilerFlags),
        "extraSwiftCFlags": \#(extraFlags.swiftCompilerFlags),
        "extraCXXFlags": \#(extraFlags.cxxCompilerFlags),
        "extraLinkerFlags": \#(extraFlags.linkerFlags)
    }
    """#)
)

private let toolsetNoRootDestinationV3 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/toolsetNoRootDestinationV3.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "runTimeTriples": {
            "\#(linuxGNUTargetTriple.tripleString)": {
                "sdkRootPath": "\#(sdkRootDir)",
                "toolsetPaths": ["/tools/otherToolsNoRoot.json"]
            }
        },
        "schemaVersion": "3.0"
    }
    """#)
)

private let toolsetRootDestinationV3 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/toolsetRootDestinationV3.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "runTimeTriples": {
            "\#(linuxGNUTargetTriple.tripleString)": {
                "sdkRootPath": "\#(sdkRootDir)",
                "toolsetPaths": ["/tools/someToolsWithRoot.json", "/tools/otherToolsNoRoot.json"]
            }
        },
        "schemaVersion": "3.0"
    }
    """#)
)

private let toolsetInvalidDestinationV3 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/toolsetInvalidDestinationV3.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "runTimeTriples": {
            "\#(linuxGNUTargetTriple.tripleString)": {
                "sdkRootPath": "\#(sdkRootDir)",
                "toolsetPaths": ["/tools/asdf.json"]
            }
        },
        "schemaVersion": "3.0"
    }
    """#)
)

private let versionInvalidDestinationV3 = (
    path: try! AbsolutePath(validating: "\(bundleRootPath)/versionInvalidDestinationV3.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "runTimeTriples": {
            "\#(linuxGNUTargetTriple.tripleString)": {
                "sdkRootPath": "\#(sdkRootDir)",
                "toolsetPaths": ["/tools/someToolsWithRoot.json"]
            }
        },
        "schemaVersion": "2.9"
    }
    """#)
)

private let usrBinTools = Dictionary(uniqueKeysWithValues: Toolset.KnownTool.allCases.map {
    ($0, try! AbsolutePath(validating: "/usr/bin/\($0.rawValue)"))
})

private let otherToolsNoRoot = (
    path: try! AbsolutePath(validating: "/tools/otherToolsNoRoot.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "schemaVersion": "1.0",
        "librarian": { "path": "\#(usrBinTools[.librarian]!)" },
        "linker": { "path": "\#(usrBinTools[.linker]!)" },
        "debugger": { "path": "\#(usrBinTools[.debugger]!)" }
    }
    """#)
)

private let cCompilerOptions = ["-fopenmp"]

private let someToolsWithRoot = (
    path: try! AbsolutePath(validating: "/tools/someToolsWithRoot.json"),
    json: ByteString(encodingAsUTF8: #"""
    {
        "schemaVersion": "1.0",
        "rootPath": "/custom",
        "cCompiler": { "extraCLIOptions": \#(cCompilerOptions) },
        "linker": { "path": "ld" },
        "librarian": { "path": "llvm-ar" },
        "debugger": { "path": "\#(usrBinTools[.debugger]!)" }
    }
    """#)
)

private let sdkRootAbsolutePath = bundleRootPath.appending(sdkRootDir)
private let toolchainBinAbsolutePath = bundleRootPath.appending(toolchainBinDir)

private let parsedDestinationV2GNU = Destination(
    hostTriple: hostTriple,
    targetTriple: linuxGNUTargetTriple,
    sdkRootDir: sdkRootAbsolutePath,
    toolset: .init(toolchainBinDir: toolchainBinAbsolutePath, buildFlags: extraFlags)
)

private let parsedDestinationV2Musl = Destination(
    hostTriple: hostTriple,
    targetTriple: linuxMuslTargetTriple,
    sdkRootDir: sdkRootAbsolutePath,
    toolset: .init(toolchainBinDir: toolchainBinAbsolutePath, buildFlags: extraFlags)
)

private let parsedToolsetNoRootDestinationV3 = Destination(
    targetTriple: linuxGNUTargetTriple,
    sdkRootDir: bundleRootPath.appending(sdkRootDir),
    toolset: .init(
        knownTools: [
            .librarian: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.librarian]!)")),
            .linker: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.linker]!)")),
            .debugger: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.debugger]!)")),
        ],
        rootPaths: []
    )
)

private let parsedToolsetRootDestinationV3 = Destination(
    targetTriple: linuxGNUTargetTriple,
    sdkRootDir: bundleRootPath.appending(sdkRootDir),
    toolset: .init(
        knownTools: [
            .cCompiler: .init(extraCLIOptions: cCompilerOptions),
            .librarian: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.librarian]!)")),
            .linker: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.linker]!)")),
            .debugger: .init(path: try! AbsolutePath(validating: "\(usrBinTools[.debugger]!)")),
        ],
        rootPaths: [try! AbsolutePath(validating: "/custom")]
    )
)

final class DestinationTests: XCTestCase {
    func testDestinationCodable() throws {
        let fs = InMemoryFileSystem()
        try fs.createDirectory(.init(validating: "/tools"))
        try fs.createDirectory(.init(validating: "/tmp"))
        try fs.createDirectory(.init(validating: "\(bundleRootPath)"))
        for testFile in [
            destinationV1,
            destinationV2,
            toolsetNoRootDestinationV3,
            toolsetRootDestinationV3,
            toolsetInvalidDestinationV3,
            versionInvalidDestinationV3,
            otherToolsNoRoot,
            someToolsWithRoot,
        ] {
            try fs.writeFileContents(testFile.path, bytes: testFile.json)
        }

        let system = ObservabilitySystem.makeForTesting()
        let observability = system.topScope

        let destinationV1Decoded = try Destination.decode(
            fromFile: destinationV1.path,
            fileSystem: fs,
            observabilityScope: observability
        )

        var flagsWithoutLinkerFlags = extraFlags
        flagsWithoutLinkerFlags.linkerFlags = []

        XCTAssertEqual(
            destinationV1Decoded,
            [
                Destination(
                    targetTriple: linuxGNUTargetTriple,
                    sdkRootDir: sdkRootAbsolutePath,
                    toolset: .init(toolchainBinDir: toolchainBinAbsolutePath, buildFlags: flagsWithoutLinkerFlags)
                ),
            ]
        )

        let destinationV2Decoded = try Destination.decode(
            fromFile: destinationV2.path,
            fileSystem: fs,
            observabilityScope: observability
        )

        XCTAssertEqual(destinationV2Decoded, [parsedDestinationV2GNU])

        let toolsetNoRootDestinationV3Decoded = try Destination.decode(
            fromFile: toolsetNoRootDestinationV3.path,
            fileSystem: fs,
            observabilityScope: observability
        )

        XCTAssertEqual(toolsetNoRootDestinationV3Decoded, [parsedToolsetNoRootDestinationV3])

        let toolsetRootDestinationV3Decoded = try Destination.decode(
            fromFile: toolsetRootDestinationV3.path,
            fileSystem: fs,
            observabilityScope: observability
        )

        XCTAssertEqual(toolsetRootDestinationV3Decoded, [parsedToolsetRootDestinationV3])

        XCTAssertThrowsError(try Destination.decode(
            fromFile: toolsetInvalidDestinationV3.path,
            fileSystem: fs,
            observabilityScope: observability
        ))
        XCTAssertThrowsError(try Destination.decode(
            fromFile: versionInvalidDestinationV3.path,
            fileSystem: fs,
            observabilityScope: observability
        ))
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
                            destinations: [parsedDestinationV2GNU]
                        ),
                    ],
                    "id2": [
                        .init(
                            metadata: .init(
                                path: "id2",
                                supportedTriples: []
                            ),
                            destinations: [parsedDestinationV2GNU]
                        ),
                    ],
                    "id3": [
                        .init(
                            metadata: .init(
                                path: "id3",
                                supportedTriples: [hostTriple]
                            ),
                            destinations: [parsedDestinationV2Musl]
                        ),
                    ],
                ]
            ),
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
