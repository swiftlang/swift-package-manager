//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2021 Apple Inc. and the Swift project authors
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

class PackageModelTests: XCTestCase {
    func testProductTypeCodable() throws {
        struct Foo: Codable, Equatable {
            var type: ProductType
        }

        func checkCodable(_ type: ProductType) {
            do {
                let foo = Foo(type: type)
                let data = try JSONEncoder.makeWithDefaults().encode(foo)
                let decodedFoo = try JSONDecoder.makeWithDefaults().decode(Foo.self, from: data)
                XCTAssertEqual(foo, decodedFoo)
            } catch {
                XCTFail("\(error)")
            }
        }

        checkCodable(.library(.automatic))
        checkCodable(.library(.static))
        checkCodable(.library(.dynamic))
        checkCodable(.executable)
        checkCodable(.test)
    }

    func testProductFilterCodable() throws {
        // Test ProductFilter.everything
        try {
            let data = try JSONEncoder().encode(ProductFilter.everything)
            let decoded = try JSONDecoder().decode(ProductFilter.self, from: data)
            XCTAssertEqual(decoded, ProductFilter.everything)
        }()
        // Test ProductFilter.specific(), including that the order is normalized
        try {
            let data = try JSONEncoder().encode(ProductFilter.specific(["Bar", "Foo"]))
            let decoded = try JSONDecoder().decode(ProductFilter.self, from: data)
            XCTAssertEqual(decoded, ProductFilter.specific(["Foo", "Bar"]))
        }()
    }

    func testAndroidCompilerFlags() throws {
        let triple = try Triple("x86_64-unknown-linux-android")
        let sdkDir = AbsolutePath("/some/path/to/an/SDK.sdk")
        let toolchainPath = AbsolutePath("/some/path/to/a/toolchain.xctoolchain")

        let destination = Destination(
            targetTriple: triple,
            toolset: .init(toolchainBinDir: toolchainPath.appending(components: "usr", "bin"), buildFlags: .init()),
            pathsConfiguration: .init(sdkRootPath: sdkDir)
        )

        XCTAssertEqual(
            try UserToolchain.deriveSwiftCFlags(triple: triple, destination: destination, environment: .process()),
            [
                // Needed when cross‐compiling for Android. 2020‐03‐01
                "-sdk", sdkDir.pathString,
            ]
        )
    }

    func testWindowsLibrarianSelection() throws {
        // tiny PE binary from: https://archive.is/w01DO
        let contents: [UInt8] = [
            0x4D, 0x5A, 0x00, 0x00, 0x50, 0x45, 0x00, 0x00, 0x4C, 0x01, 0x01, 0x00,
            0x6A, 0x2A, 0x58, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x04, 0x00, 0x03, 0x01, 0x0B, 0x01, 0x08, 0x00, 0x04, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00,
            0x04, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x68, 0x00, 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x02,
        ]

        #if os(Windows)
        let suffix = ".exe"
        #else
        let suffix = ""
        #endif

        let triple = try Triple("x86_64-unknown-windows-msvc")
        let fs = TSCBasic.localFileSystem

        try withTemporaryFile { [contents] _ in
            try withTemporaryDirectory(removeTreeOnDeinit: true) { [contents] tmp in
                let bin = tmp.appending("bin")
                try fs.createDirectory(bin)

                let lld = bin.appending("lld-link\(suffix)")
                try fs.writeFileContents(lld, bytes: ByteString(contents))

                let not = bin.appending("not-link\(suffix)")
                try fs.writeFileContents(not, bytes: ByteString(contents))

                #if !os(Windows)
                try fs.chmod(.executable, path: lld, options: [])
                try fs.chmod(.executable, path: not, options: [])
                #endif

                try XCTAssertEqual(
                    UserToolchain.determineLibrarian(
                        triple: triple, binDirectories: [bin], useXcrun: false, environment: [:], searchPaths: [],
                        extraSwiftFlags: ["-Xswiftc", "-use-ld=lld"]
                    ),
                    lld
                )

                try XCTAssertEqual(
                    UserToolchain.determineLibrarian(
                        triple: triple, binDirectories: [bin], useXcrun: false, environment: [:], searchPaths: [],
                        extraSwiftFlags: ["-Xswiftc", "-use-ld=not-link\(suffix)"]
                    ),
                    not
                )

                try XCTAssertThrowsError(
                    UserToolchain.determineLibrarian(
                        triple: triple, binDirectories: [bin], useXcrun: false, environment: [:], searchPaths: [],
                        extraSwiftFlags: []
                    )
                )
            }
        }
    }
}
